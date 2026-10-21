import Vocabulary

## Gives a Config for tests. The host builds the real one.
Config := [].{

	## A Config with seed 0, no assets and no args. Give it to `init` in a test.
	empty : Vocabulary.Config
	empty = { seed: 0, assets: [], args: [] }
}

expect Config.empty == { seed: 0, assets: [], args: [] }
