debug:
	odin build . -out:out/program.exe
	./out/program.exe

release:
	odin build . -out:out/program.exe -o=speed
	./out/program.exe