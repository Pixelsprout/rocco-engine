import Vocabulary

# The Config a test gives init. The host builds the real one.
Config := [].{
	empty : Vocabulary.Config
	empty = { seed: 0, assets: [] }
}

expect Config.empty == { seed: 0, assets: [] }
