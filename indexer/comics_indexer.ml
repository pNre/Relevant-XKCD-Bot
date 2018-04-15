module type ComicsIndexer = sig
  val index_comics: Sqlite3.db -> (int -> int -> unit Lwt.t) -> unit Lwt.t
end
