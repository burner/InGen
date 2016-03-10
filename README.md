InGen
=========

![alt text](https://travis-ci.org/burner/InGen.svg?branch=master)

InGen is a dependency injection Framework.

Example
-------

```d
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
```
