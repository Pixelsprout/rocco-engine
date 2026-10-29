import QueryResults
import Vocabulary

## Builds the Tell Commands and the Listen Queries of a port, and reads the
## messages that `step` gets. A port is a named channel between your game and a
## Driver or an extension. Send a Listen in `Scene.queries` every step for each
## port that you want to read.
Port := [].{

	## Sends `msg` to `port`. A Driver reads it in the `step` reply.
	tell : Str, Str -> Vocabulary.Command
	tell = |port, msg| Tell({ port, msg })

	## Asks for the messages sent to `port` since the last step.
	listen : Str -> Vocabulary.Query
	listen = |port| Listen(port)

	## The messages that `port` received, in arrival order.
	messages : Vocabulary.QueryResults, Str -> List(Str)
	messages = |results, port| List.fold(
		results.ports,
		[],
		|msgs, row| if row.port == port {
			msgs.append(row.msg)
		} else {
			msgs
		},
	)
}

expect Port.tell("town", "hi") == Tell({ port: "town", msg: "hi" })
expect Port.listen("town") == Listen("town")
expect Port.messages(QueryResults.empty, "town") == []
expect Port.messages({ ..QueryResults.empty, ports: [{ port: "a", msg: "1" }, { port: "town", msg: "2" }, { port: "town", msg: "" }] }, "town") == ["2", ""]
