package af

import "core:fmt"

LogSeverity :: enum {
	Debug,
	Info,
	Warning,
	FatalError,
}

debug_log :: proc(
	format: string,
	msg: ..any,
	loc := #caller_location,
	severity := LogSeverity.Debug,
) {
	severity_str: string
	switch severity {
	case .Debug:
		severity_str = "DEBUG"
	case .Info:
		severity_str = "INFO"
	case .Warning:
		severity_str = "WARNING"
	case .FatalError:
		severity_str = "FATAL ERROR"
	}


	fmt.printf("[%s] %s:%d:%d - \t", severity_str, loc.file_path, loc.line, loc.column)
	fmt.printf(format, ..msg)
	fmt.printf("\n")

	if severity == .FatalError {
		panic("Exiting due to fatal error")
	}
}
