import pf.Vocabulary

Display := [].{

	window : Vocabulary.Config, Vocabulary.Window -> Vocabulary.Window
	window = |config, window| if config.args.contains("--retina-1080") {
		..window,
		width: 960,
		height: 540,
		high_dpi: Bool.True,
	} else {
		..window,
		width: 1920,
		height: 1080,
		high_dpi: Bool.False,
	}
}
