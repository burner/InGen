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
class InGenFactory {
	import std.traits;
	import std.stdio;
	import std.array : appender;

	private static void testEmplaceChunk(void[] chunk, size_t typeSize, 
			size_t typeAlignment, string typeName) @nogc pure nothrow
	{
	    assert(chunk.length >= typeSize, "emplace: Chunk size too small.");
	    assert((cast(size_t)chunk.ptr) % typeAlignment == 0, 
			"emplace: Chunk is not aligned."
		);
	}

	private static T emplace(T, Args...)(void[] chunk, auto ref Args args)
		@trusted if (is(T == class))
	{
	    enum classSize = __traits(classInstanceSize, T);
	    testEmplaceChunk(chunk, classSize, classInstanceAlignment!T, T.stringof);
	    auto result = cast(T) chunk.ptr;
	
	    // Initialize the object in its pre-ctor state
	    chunk[0 .. classSize] = typeid(T).initializer[];

		// Set all the injectables
		makeClass(result, args);
	
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

	static Injectable[string] instances;
	static TypeInfo_Class[TypeInfo] interfaces;

	static T make(T,A...)(auto ref A args) @safe {
		import core.memory : GC;
		static if(isInterface!T) {
			/*auto mem = new void[InGenFactory.interfaces[typeid(T)].tsize];
			return emplace!T(mem, args);
			*/
			assert(false);
		} else {
			auto mem = new void[__traits(classInstanceSize, T)];
			return emplace!T(mem, args);
		}
	}

	static void register(Inter,Impl)() {
		InGenFactory.interfaces[typeid(Inter)] = Impl.classinfo;
	}

	private static auto makeInterface(T,A...)(A args) {
		assert(false);
	}

	private static void makeClass(T,A...)(ref T ret, A args) {
		//auto ret = new T(args);
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
					} else if(jt.length > 0 && jt[0] == InGenEnums.New) {
						__traits(getMember, ret, it) = 
							InGenFactory.make!Type(jt[1 .. $]);
					}
				}
			}
		}

		//return ret;
	}

	template isInterface(T)
	{
		enum isInterface = is(T == interface);
	}

	private static string buildString(T,A)(A a) {
		return T.stringof ~ "(" ~ a.toString() ~ ")";
	}
}

version(unittest) {

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

//enum InGen;

class TestClass {
	@InGen(10) TestInj1 inj1;
	int notInjected;
	@InGenNew("Foo") TestInj2 inj2;
	@InGen() TestInj3 inj3;
}

class TestClass2 {
	TestInj1 inj1;
}

interface SomeInterface {
}

class InterImpl : SomeInterface {

}

}

@safe unittest {
	InGenFactory.register!(SomeInterface, InterImpl)();
	//auto ii = InGenFactory.make!SomeInterface();
	auto tc = new TestClass();
	tc = InGenFactory.make!TestClass();
	assert(tc.inj1.a == 10);
	assert(tc.inj2.s == "Foo");

	auto tc2 = InGenFactory.make!TestClass2();
	assert(tc2.inj1 is null);
	tc = InGenFactory.make!TestClass();

	assert(tc.inj1.a == 10);
	assert(tc.inj2.s == "Foo");
	assert(tc.inj3 !is null);
}
