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
    let _ = bind_text statement 1 query
    and _ = bind_text statement 2 (Format.sprintf "%%%s%%" query)
    and _ = bind_text statement 3 (Format.sprintf "%%%s%%" query) in
    let rec stepper results =
      match step statement with
      | Rc.ROW ->
        let row = row_data statement in
        let id = Data.to_int_exn row.(0) |> Int.to_string in
        let title = Data.to_string_exn row.(1)
        and uri = Data.to_string_exn row.(2)
        and reference = Uri.make ~scheme:"https" ~host:"xkcd.com" ~path:id ()
        and (w, h) =
          try
            let w = Data.to_int_exn row.(3)
            and h = Data.to_int_exn row.(4) in
            (w, h)
          with _ ->
            (0, 0) in
        stepper ({id=id; uri=(Uri.of_string uri); title=title; width=w; height=h; reference=reference} :: results)
      | _ -> results in
    stepper []
end
