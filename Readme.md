# Odin - Application Framework

A simple OpenGL rendering engine with a processing-like API. 
I made it mainly for learning purposes, and because I preferred the processing API, and I found the RayLib API to be a bit unintuitive in some respects.

I have decided to keep it focused on rendering, and I have decided to omit an Audio API from this framework.
If I end up making something decent on that front, I will add it here though.

Remaining TODO:
- Font fallbacks for missing glyphs
- UTF-8 text shaping somehow

## Suggested usage

Clone the repo, delete everything in `main`, and then start adding your own code around there while trying to touch the `af` package files as little as possible. Sometimes, you may find that the existing implementations are lacking, have wrong defaults, or you need some new feature that I haven't added yet (like additional vertex attributes and shaders, for example), which is when you would amend the `af` package with your own stuff.

This is the best way to shield yourself from upstream API changes, and to have the most flexibility and control.
It also means that I don't have to bend over backwards to make a framework that does everything for everyone, but in a mediocre way.

## Backstory

I was previously writing this in C#, and I had decided to move to another language because I found it quite hard to prevent allocations, especially when using and drawing strings, or using third-party libraries.

I was able to code a lot of it in pure C, but it didn't have a hashmap datastructure, which I needed for the text rendering part.
I didn't want to use some random hashmap from GitHub, nor did I want to use C++. I also was not particularly fond of the one I wrote myself.
I am using Odin, because the language seems to be very promising - it has that C-like simplicity, but fixes a lot of the bad syntax and certain inconvenient aspects of the language. 
The vendor packages are also very helpful for my lazy ass.

The tooling is still a bit lacking, however. The language server could use some improvements though:
- renaming variables with F2 is not possible
- It will show a lot of false positive errors for unsaved files, almost as if it is using a less accurate algorithm to provide the red lines for saved and unsaved files

Despite that, it is still more fun to use than C or C++. If I had to design my own language, it would be very similar to this one.