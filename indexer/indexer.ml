open Comics_indexer
open Xkcd_indexer
open Sqlite3

let indexers = [
  ("xkcd", (module XkcdIndexer: ComicsIndexer));
]

let log_progress indexer current total =
  Lwt_io.printf "[%s] %d/%d\n" indexer current total

let start_indexers db =
  indexers
  |> List.map (fun ((name, indexer)) ->
    let module Indexer = (val indexer: ComicsIndexer) in
    Indexer.index_comics db (log_progress name))
  |> Lwt.join

let () =
  match Sys.argv with
  | args when Array.length args > 1 ->
    let db = db_open args.(1) in
    start_indexers db
    |> Lwt_main.run
    |> ignore
  | _ -> failwith "Not enough arguments"
