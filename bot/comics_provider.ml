type comic = {
  id: string;
  uri: Uri.t;
  title: string;
  width: int;
  height: int
}

module type ComicsProvider = sig
  val search_matching: Sqlite3.db -> string -> comic list
end
