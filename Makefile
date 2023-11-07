debug-build:
	odin build . -out:out/debug/program.exe -strict-style -debug

debug-run: debug-build
	out/debug/program.exe


release-build:
	odin build . -out:out/release/program.exe -o=speed -strict-style

release-run: release-build
	out/release/program.exe