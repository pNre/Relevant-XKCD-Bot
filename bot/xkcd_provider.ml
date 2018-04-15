open Comics_provider
open Sqlite3

module XkcdProvider: ComicsProvider = struct
  let search_matching db query =
    let statement = prepare db "
      SELECT id, title, uri, w, h
        FROM xkcd
       WHERE id = ?
          OR title LIKE ?
          OR alt LIKE ?" in
    let _ = bind statement 1 (TEXT query)
    and _ = bind statement 2 (TEXT (Format.sprintf "%%%s%%" query))
    and _ = bind statement 3 (TEXT (Format.sprintf "%%%s%%" query)) in
    let rec stepper results =
      match step statement with
      | Rc.ROW ->
        let row = row_data statement in
        let id = Data.to_string row.(0)
        and title = Data.to_string row.(1)
        and uri = Data.to_string row.(2)
        and (w, h) =
          try
            (int_of_string(Data.to_string row.(3)), int_of_string(Data.to_string row.(4)))
          with _ ->
            (0, 0) in
        stepper ({id=id; uri=(Uri.of_string uri); title=title; width=w; height=h} :: results)
      | _ -> results in
    stepper []
end
