import pf.Vocabulary
import pf.Config
import pf.Launch

Display := [].{

	window : Vocabulary.Config, Vocabulary.Window -> Vocabulary.Window
	window = |config, base| if (config.args.contains("--hosted-compat")) {
		..base,
		width: 960,
		height: 540,
		high_dpi: Bool.False,
	} else if (config.args.contains("--retina-1080")) {
		..base,
		width: 960,
		height: 540,
		high_dpi: Bool.True,
	} else {
		..base,
		width: 1920,
		height: 1080,
		high_dpi: Bool.False,
	}
}

expect {
	window = Display.window({ ..Config.empty, args: ["--hosted-compat"] }, Launch.default.window)
	window.width == 960 and window.height == 540 and !window.high_dpi
}

expect {
	window = Display.window({ ..Config.empty, args: ["--retina-1080"] }, Launch.default.window)
	window.width == 960 and window.height == 540 and window.high_dpi
}

expect {
	window = Display.window(Config.empty, Launch.default.window)
	window.width == 1920 and window.height == 1080 and !window.high_dpi
}
