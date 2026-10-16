import Vocabulary

# Builds QueryResults for tests.
QueryResults := [].{
	# What the first step gets.
	empty : Vocabulary.QueryResults
	empty = { contacts: [], rays: [], overlaps: [] }
}

expect QueryResults.empty.contacts.is_empty()
