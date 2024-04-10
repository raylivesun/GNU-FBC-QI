'' to the name of the template filesystem and the name of the files 
Declare Sub Test Overload(update As Double)
 'Dimension a static variable
 Static cnt As Integer
 'Increment the count
 cnt += 1

 Print "In Test";cnt;" time(s)."
End 

'Dimension working variable
Dim i As Integer

'Call sub 10 times
For i = 0 To 10 
    Print "In Test";cnt;" time(s).";i;"Call sub 10 times"
Next

Sleep
End