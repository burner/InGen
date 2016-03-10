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

	static auto make(T,A...)(auto ref A args) {
		static if(isInterface!T) {
			return InGenFactory.makeInterface!T(args);
		} else {
			import core.memory : GC;
			auto mem = new void[__traits(classInstanceSize, T)];
			return emplace!T(mem, args);
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
	
	static void testEmplaceChunk(void[] chunk, size_t typeSize, 
			size_t typeAlignment, string typeName) @nogc pure nothrow
	{
	    assert(chunk.length >= typeSize, "emplace: Chunk size too small.");
	    assert((cast(size_t)chunk.ptr) % typeAlignment == 0, 
			"emplace: Chunk is not aligned."
		);
	}

	static T emplace(T, Args...)(void[] chunk, auto ref Args args)
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
					} else if(jt.length > 0 && jt[0] == InGenEnums.New) {
						__traits(getMember, ret, it) = 
							InGenFactory.make!Type(jt[1 .. $]);
					}
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

//enum InGen;

class TestClass {
	/** InGen(10) will check if there is already an instance of TestInj1 which
	  was constructed with the value 10. If it exists, it is returned.
	  Otherwise a TestInj1 is created with 10 passed to its constructor.
	  This created instance is additionally stored inside the InGenFactory.
	*/
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

unittest {
	InGenFactory.register!(SomeInterface, InterImpl)();
	auto ii = InGenFactory.make!SomeInterface();
	InterImpl iim = cast(InterImpl)ii;
	InGenFactory.inject(iim);
	assert(iim !is null);
}

unittest {
	auto tc = new TestClass();
	tc = InGenFactory.make!TestClass();
	assert(tc.inj1.a == 10);
	assert(tc.inj2.s == "Foo");

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
