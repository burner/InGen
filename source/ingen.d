module ingen;

import std.typecons;

interface Injectable {
}

enum InGenEnums {
	Singleton,
	New,
}

struct InGen {
	static auto opCall(T...)(T args) {
		return tuple(InGenEnums.Singleton, args);
	}
}

struct InGenNew {
	static auto opCall(T...)(T args) {
		return tuple(InGenEnums.New, args);
	}
}

private {
T emplace(T, Args...)(void[] chunk, auto ref Args args)
	if (is(T == class))
{
	import std.traits;
	enum classSize = __traits(classInstanceSize, T);
	testEmplaceChunk(chunk, classSize, classInstanceAlignment!T, T.stringof);
	auto result = cast(T) chunk.ptr;

	// Initialize the object in its pre-ctor state
	chunk[0 .. classSize] = typeid(T).init[];
	InGenFactory.makeClass(result, args);

	// Call the ctor if any
	static if (is(typeof(result.__ctor(args))))
	{
		// T defines a genuine constructor accepting args
		// Go the classic route: write .init first, then call ctor
		result.__ctor(args);
	}
	else
	{
		static assert(args.length == 0 && !is(typeof(&T.__ctor)),
				"Don't know how to initialize an object of type "
				~ T.stringof ~ " with arguments " ~ Args.stringof);
	}
	return result;
}

T* emplace(T, Args...)(void[] chunk, auto ref Args args)
	if (!is(T == class))
{
	testEmplaceChunk(chunk, T.sizeof, T.alignof, T.stringof);
	return emplace(cast(T*) chunk.ptr, args);
}

package ref UT emplaceRef(UT, Args...)(ref UT chunk, auto ref Args args)
if (is(UT == Unqual!UT))
{
	return emplaceImpl!UT(chunk, args);
}
// ditto
package ref UT emplaceRef(T, UT, Args...)(ref UT chunk, auto ref Args args)
if (is(UT == Unqual!T) && !is(T == UT))
{
	return emplaceImpl!T(chunk, args);
}


private template emplaceImpl(T)
{
	alias UT = Unqual!T;

	ref UT emplaceImpl()(ref UT chunk)
	{
		static assert (is(typeof({static T i;})),
			convFormat("Cannot emplace a %1$s because %1$s.this() is annotated with @disable.", T.stringof));

		return emplaceInitializer(chunk);
	}

	static if (!is(T == struct))
	ref UT emplaceImpl(Arg)(ref UT chunk, auto ref Arg arg)
	{
		static assert(is(typeof({T t = arg;})),
			convFormat("%s cannot be emplaced from a %s.", T.stringof, Arg.stringof));

		static if (isStaticArray!T)
		{
			alias UArg = Unqual!Arg;
			alias E = ElementEncodingType!(typeof(T.init[]));
			alias UE = Unqual!E;
			enum n = T.length;

			static if (is(Arg : T))
			{
				//Matching static array
				static if (!hasElaborateAssign!UT && isAssignable!(UT, Arg))
					chunk = arg;
				else static if (is(UArg == UT))
				{
					import core.stdc.string : memcpy;
					// This is known to be safe as the two values are the same
					// type and the source (arg) should be initialized
					() @trusted { memcpy(&chunk, &arg, T.sizeof); }();
					static if (hasElaborateCopyConstructor!T)
						_postblitRecurse(chunk);
				}
				else
					.emplaceImpl!T(chunk, cast(T)arg);
			}
			else static if (is(Arg : E[]))
			{
				//Matching dynamic array
				static if (!hasElaborateAssign!UT && is(typeof(chunk[] = arg[])))
					chunk[] = arg[];
				else static if (is(Unqual!(ElementEncodingType!Arg) == UE))
				{
					import core.stdc.string : memcpy;
					assert(n == chunk.length, "Array length missmatch in emplace");

					// This is unsafe as long as the length match is a
					// precondition and not an unconditional exception
					memcpy(&chunk, arg.ptr, T.sizeof);

					static if (hasElaborateCopyConstructor!T)
						_postblitRecurse(chunk);
				}
				else
					.emplaceImpl!T(chunk, cast(E[])arg);
			}
			else static if (is(Arg : E))
			{
				//Case matching single element to array.
				static if (!hasElaborateAssign!UT && is(typeof(chunk[] = arg)))
					chunk[] = arg;
				else static if (is(UArg == Unqual!E))
				{
					import core.stdc.string : memcpy;

					foreach(i; 0 .. n)
					{
						// This is known to be safe as the two values are the same
						// type and the source (arg) should be initialized
						() @trusted { memcpy(&(chunk[i]), &arg, E.sizeof); }();
					}

					static if (hasElaborateCopyConstructor!T)
						_postblitRecurse(chunk);
				}
				else
					//Alias this. Coerce.
					.emplaceImpl!T(chunk, cast(E)arg);
			}
			else static if (is(typeof(.emplaceImpl!E(chunk[0], arg))))
			{
				//Final case for everything else:
				//Types that don't match (int to uint[2])
				//Recursion for multidimensions
				static if (!hasElaborateAssign!UT && is(typeof(chunk[] = arg)))
					chunk[] = arg;
				else
					foreach(i; 0 .. n)
						.emplaceImpl!E(chunk[i], arg);
			}
			else
				static assert(0, convFormat("Sorry, this implementation doesn't know how to emplace a %s with a %s", T.stringof, Arg.stringof));

			return chunk;
		}
		else
		{
			chunk = arg;
			return chunk;
		}
	}
}

private void testEmplaceChunk(void[] chunk, size_t typeSize, size_t typeAlignment, string typeName) @nogc pure nothrow
{
	assert(chunk.length >= typeSize, "emplace: Chunk size too small.");
	assert((cast(size_t)chunk.ptr) % typeAlignment == 0, "emplace: Chunk is not aligned.");
}

//emplace helper functions
private ref T emplaceInitializer(T)(ref T chunk) @trusted pure nothrow
{
	static if (!hasElaborateAssign!T && isAssignable!T)
		chunk = T.init;
	else
	{
		import core.stdc.string : memcpy;
		static immutable T init = T.init;
		memcpy(&chunk, &init, T.sizeof);
	}
	return chunk;
}

T* emplace(T)(T* chunk) @safe pure nothrow
{
	emplaceImpl!T(*chunk);
	return chunk;
}

T* emplace(T, Args...)(T* chunk, auto ref Args args)
if (!is(T == struct) && Args.length == 1)
{
	emplaceImpl!T(*chunk, args);
	return chunk;
}
/// ditto
T* emplace(T, Args...)(T* chunk, auto ref Args args)
if (is(T == struct))
{
	emplaceImpl!T(*chunk, args);
	return chunk;
}
}

class InGenFactory {
	import std.traits;
	import std.stdio;
	import std.array : appender;

	static auto make(T,A...)(auto ref A args) {
		static if(isInterface!T) {
			return InGenFactory.makeInterface!T(args);
		} else {
			import core.memory : GC;
			auto mem = new void[__traits(classInstanceSize, T)];
			return ingenEmplace!T(mem, args);
		}
	}

	static T get(T)() {
		enum s = buildString!T(tuple(InGenEnums.Singleton));
		if(auto tmp = s in InGenFactory.instances) {
			return cast(T)*tmp;
		}

		throw new Exception("Requested instance of Object " ~ T.stringof ~ 
			" does not exists."
		);
	}

	static void register(Inter,Impl)() {
		InGenFactory.interfaces[typeid(Inter)] = Impl.classinfo;
	}

	static void inject(T)(ref T cls) {
		makeClass(cls);
	}

	private: 
	
	static T ingenEmplace(T, Args...)(ref void[] chunk, auto ref Args args)
		@trusted if (is(T == class))
	{
		T result = emplace!T(chunk, args);
		return result;
	}

	static Injectable[string] instances;
	static TypeInfo_Class[TypeInfo] interfaces;

	static auto makeInterface(T,A...)(auto ref A args) {
		return InGenFactory.interfaces[typeid(T)].create(args);
	}

	static void makeClass(T,A...)(ref T ret, auto ref A args) {
		foreach(it; __traits(allMembers, T)) {
			foreach(jt; __traits(getAttributes, __traits(getMember, T, it))) {
				static if(isTuple!(typeof(jt))) {
					alias Type = typeof(__traits(getMember, T, it));
					if(jt.length > 0 && jt[0] == InGenEnums.Singleton) {
						string s = buildString!Type(jt);
						if(auto tmp = s in InGenFactory.instances) {
							__traits(getMember, ret, it) = cast(Type)*tmp;
						} else {
							auto tmp = InGenFactory.make!Type(jt[1 .. $]);
							InGenFactory.instances[s] = tmp;
							__traits(getMember, ret, it) = tmp;
						}
						recreateStandaloneInjectabiles(
							__traits(getMember, ret, it)
						);
					} else if(jt.length > 0 && jt[0] == InGenEnums.New) {
						__traits(getMember, ret, it) = 
							InGenFactory.make!Type(jt[1 .. $]);
						recreateStandaloneInjectabiles(
							__traits(getMember, ret, it)
						);
					}
				}
			}
		}
	}

	static void recreateStandaloneInjectabiles(T)(ref T t) {
		foreach(it; __traits(allMembers, T)) {
			foreach(jt; __traits(getAttributes, __traits(getMember, T, it))) {
				static if(isTuple!(typeof(jt))) {
					alias Type = typeof(__traits(getMember, T, it));
					if(jt.length > 0 && jt[0] == InGenEnums.New) {
						__traits(getMember, t, it) = 
							InGenFactory.make!Type(jt[1 .. $]);
					}
					recreateStandaloneInjectabiles(
						__traits(getMember, t, it)
					);
				}
			}
		}
	}

	template isInterface(T)
	{
		enum isInterface = is(T == interface);
	}

	static string buildString(T,A)(A a) {
		return T.stringof ~ "(" ~ a.toString() ~ ")";
	}
}

version(unittest) {

/** Everything that should be injected must be a class and implement the
  interface Injectable. The implementation is trivial as it is an empty
  interface.
*/
class TestInj1 : Injectable {
	int a;
	string someString;
	this(int a) @safe {
		this.a = a;
	}
}

class TestInj2 : Injectable {
	string s;
	this(string s) @safe {
		this.s = s;
	}
}

class TestInj3 : Injectable {
	this() { }
}

struct TestStruct {
	int[] a;
	string f;
}

//enum InGen;

class TestClass : Injectable {
	/** InGen(10) will check if there is already an instance of TestInj1 which
	  was constructed with the value 10. If it exists, it is returned.
	  Otherwise a TestInj1 is created with 10 passed to its constructor.
	  This created instance is additionally stored inside the InGenFactory.
	*/
	@InGen(10) TestInj1 inj1;
	int notInjected;
	@InGenNew("Foo") TestInj2 inj2;
	@InGen() TestInj3 inj3;

	TestStruct ts;

	this() {
		assert(this.inj1 !is null);
		assert(this.inj2 !is null);
		assert(this.inj3 !is null);
	}
}

class TestClass2 {
	TestInj1 inj1;
}

class TestClass3 {
	@InGen() TestClass tc;
	this() {
		assert(this.tc !is null);
		assert(this.tc.inj1 !is null);
		assert(this.tc.inj2 !is null);
		assert(this.tc.inj3 !is null);
	}
}

interface SomeInterface {
}

class InterImpl : SomeInterface {

}

}

unittest {
	InGenFactory.register!(SomeInterface, InterImpl)();
	auto ii = InGenFactory.make!SomeInterface();
	InterImpl iim = cast(InterImpl)ii;
	InGenFactory.inject(iim);
	assert(iim !is null);
}

unittest {
	import std.array : empty;
	auto tc = InGenFactory.make!TestClass();
	assert(tc.inj1.a == 10);
	assert(tc.inj2.s == "Foo");
	assert(tc.ts.a.empty); 
	assert(tc.ts.a == ""); 

	auto tc_2 = InGenFactory.make!TestClass();
	assert(tc_2.inj1.a == 10);
	assert(tc_2.inj2.s == "Foo");

	assert(tc.inj1 is tc_2.inj1);
	assert(tc.inj2 !is tc_2.inj2); 
	assert(tc.inj3 is tc_2.inj3);

	auto tc2 = InGenFactory.make!TestClass2();
	assert(tc2.inj1 is null);

	auto tc2_2 = InGenFactory.make!TestClass2();
	assert(tc2_2.inj1 is null);
	assert(tc2 !is tc2_2);

	tc = InGenFactory.make!TestClass();

	assert(tc.inj1.a == 10);
	assert(tc.inj2.s == "Foo");
	assert(tc.inj3 !is null);

	/** get allows to get a existing instance of a class or interface.
	  In case the requested type does not exists an Exception will be thrown.
	*/
	auto ti3 = InGenFactory.get!TestInj3();
	assert(ti3 !is null);

	auto ti3_2 = InGenFactory.get!TestInj3();
	assert(ti3 is ti3_2);

	import std.exception : assertThrown;
	assertThrown(InGenFactory.get!TestInj2());
}

unittest {
	auto tc = InGenFactory.make!TestClass3();
	assert(tc !is null);
	assert(tc.tc !is null);
	assert(tc.tc.inj1 !is null);
	assert(tc.tc.inj1.a == 10);
	assert(tc.tc.inj2 !is null);
	assert(tc.tc.inj2.s == "Foo");
	assert(tc.tc.inj3 !is null);

	auto tc2 = InGenFactory.make!TestClass3();
	assert(tc2 !is null);
	assert(tc2.tc !is null);
	assert(tc2.tc.inj1 !is null);
	assert(tc2.tc.inj1.a == 10);
	assert(tc2.tc.inj2 !is null);
	assert(tc2.tc.inj2.s == "Foo");
	assert(tc2.tc.inj3 !is null);

	assert(tc.tc is tc2.tc);
	assert(tc.tc.inj1 is tc2.tc.inj1);
	assert(tc.tc.inj2 !is tc2.tc.inj2);
	assert(tc.tc.inj3 is tc2.tc.inj3);
}
