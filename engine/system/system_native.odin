#+build !freestanding
package system

import "core:fmt"
import "core:os"

Error :: os.Error
File :: os.File
File_Flags :: os.File_Flags
File_Info :: os.File_Info

args := os.args

close :: os.close
error_string :: os.error_string
exit :: os.exit
ext :: os.ext
file_size :: os.file_size
get_env :: os.get_env
is_absolute_path :: os.is_absolute_path
lookup_env :: os.lookup_env
open :: os.open
read :: os.read
read_all_directory_by_path :: os.read_all_directory_by_path
read_entire_file :: os.read_entire_file
split_path :: os.split_path
stem :: os.stem
write :: os.write
write_entire_file :: os.write_entire_file

eprintfln :: fmt.eprintfln
eprintln :: fmt.eprintln
printfln :: fmt.printfln
println :: fmt.println
