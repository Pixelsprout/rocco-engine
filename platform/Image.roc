import Vocabulary

## Finds Image ids and sizes in a Manifest, and gives the Image that your game
## starts a record update from.
Image := [].{

	## Id 0, the whole Image, a white tint and `Linear` filtering. Set `id`.
	default : Vocabulary.Image
	default = { id: 0, region: Whole, tint: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }, filter: Linear }

	## The Image id of a name in the Manifest, such as `image/coin`. Call it
	## once, in `loaded`, and keep the id in your Model. A name that is not in
	## the Manifest gives 0.
	resolve : Vocabulary.Manifest, Str -> U32
	resolve = |manifest, name| match List.find_first(manifest, |m| m.name == name) {
		Ok(m) => m.id
		Err(NotFound) => 0
	}

	## The width and height in pixels of the Image with this name, such as
	## `image/coin`. A `Px` region counts in these pixels. A name that is not
	## in the Manifest, or that is not a loaded Image, gives 0 by 0.
	size : Vocabulary.Manifest, Str -> { w : U32, h : U32 }
	size = |manifest, name| match List.find_first(manifest, |m| m.name == name) {
		Ok(m) => m.size
		Err(NotFound) => { w: 0, h: 0 }
	}
}

expect Image.default == { id: 0, region: Whole, tint: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }, filter: Linear }
expect Image.resolve([{ name: "pip", id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] }, { name: "image/coin", id: 65537, duration: 0.0, size: { w: 16, h: 8 }, clips: [] }], "image/coin") == 65537
expect Image.resolve([{ name: "image/coin", id: 0, duration: 0.0, size: { w: 0, h: 0 }, clips: [] }], "image/coin") == 0
expect Image.resolve([{ name: "image/coin", id: 1, duration: 0.0, size: { w: 16, h: 8 }, clips: [] }], "image/cion") == 0
expect Image.size([{ name: "pip", id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] }, { name: "image/coin", id: 65537, duration: 0.0, size: { w: 16, h: 8 }, clips: [] }], "image/coin") == { w: 16, h: 8 }
expect Image.size([{ name: "image/coin", id: 0, duration: 0.0, size: { w: 0, h: 0 }, clips: [] }], "image/coin") == { w: 0, h: 0 }
expect Image.size([{ name: "image/coin", id: 1, duration: 0.0, size: { w: 16, h: 8 }, clips: [] }], "image/cion") == { w: 0, h: 0 }
