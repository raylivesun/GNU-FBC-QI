' TEST_MODE : COMPILE_ONLY_FAIL

type Parent
	as integer i
	private:
	declare destructor( )
end type

destructor Parent( )
end destructor

type Child extends Parent
	declare sub test( )
end type

sub Child.test( )
	dim as Parent ptr p
	delete[] p
end sub
