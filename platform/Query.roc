import Vocabulary

# Builds the Queries a game returns in Scene.queries.
Query := [].{
	# Asks for each Contact that involves the owner's Collider.
	contacts_of : U64 -> Vocabulary.Query
	contacts_of = |owner| ContactsOf(owner)
}

expect Query.contacts_of(7) == ContactsOf(7)
