This is a small util to take an input file and output byte array syntax. 

command structure: ./exe -o path lang -i path array_name -i path array_name -o...  
lang is optional will default to c.  
array_name is optional it will derive from path when omitted. 

-or: enables rewrite  
-im: mutable   
-is: string  
-ism, -ims: both combinations work

Current version only supports c, other language paths will fail. Looking to support c++ specific (std::array and std::string), zig since its written in zig, and maybe rust but I haven't used rust before.
String currently just switches to char instead of unsigned char and adds a null terminator on the end however I do want to make a specific string version that outputs characters instead of bytes in hex form. 
Will add a way to get null terminated byte format also for where that still makes sense.
