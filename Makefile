debug:
	odin build . -out:out/program.exe -strict-style
	./out/program.exe

release:
	odin build . -out:out/program.exe -o=speed  -strict-style
	./out/program.exe