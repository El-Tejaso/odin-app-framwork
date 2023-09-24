package af

import "core:fmt"

DebugLog :: proc(format: string, msg: ..any, loc := #caller_location, should_panic:=false) {
	fmt.printf("%s:%d:%d - \t", loc.file_path, loc.line, loc.column)
	fmt.printf(format, ..msg)
	fmt.printf("\n")

	if should_panic {
		panic("Exiting due to critical error")
	}
}