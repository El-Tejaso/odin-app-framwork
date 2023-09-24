# Odin - minimal application framework

A minimal application framework with a Processing-like API, and a fraction of the features.
I was initially writing this in C#, but then I realized I was doing all sorts of hacks to reduce memory allocations, and even making my own zero-allocation string class. But then why don't I just write it in C? Also, I wanted to use the signed-distance field text rendering that is in FreeType, but C# didn't seem to have these bindings. So I started porting the framwork to C. It was great at first, but then there came a point where I needed a hashmap. I wrote my own, but I was not convinced that it was very good, and I didn't want to spend the next month optimizing my hashmap, or downloading someone elses off github and reviewing their code. 

Then I found this Odin language. It seems that the creator has tried to keep it as C-like as possible with little to no 'magic', while fixing a lot of the issues that I and others have with the language. 
There are also a lot of language features that are very useful for the kind of programming that I usually do, like hashmaps, but also vector/matrix/quaternion as a part of the "core" library. 
The "vendor" libs are also very useful, and include bindings to things like opengl, sdl, freetype, glfw, raylib, etc (basically all the cool C libs that you would usually have to write in C for).
I have only started programming in it a week ago, but it seems like it is very close to the ideal programming language for the things I intend to program. (TODO: @Myself to confirm/deny this in 6 months time)