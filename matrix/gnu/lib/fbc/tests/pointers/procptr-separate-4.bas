' TEST_MODE : COMPILE_ONLY_OK

Type Parent Extends Object
	Declare Virtual Operator Let (Byref p As Parent)
End Type

Operator Parent.Let (Byref p As Parent)
End Operator

Type Child Extends Parent
	Declare Sub s ()
End Type

Sub Child.s ()
	Dim As Parent p
	p = Cast(Parent, This)
End Sub
