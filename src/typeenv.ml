open Types

type t = (var_name * poly_type) list


let empty = []


let to_list tyenv = tyenv


let from_list lst = lst


let map f tyenv = List.map f tyenv


let rec add (tyenv : t) (varnm : var_name) (pty : poly_type) =
  match tyenv with
  | []                                -> (varnm, pty) :: []
  | (vn, pt) :: tail  when vn = varnm -> (varnm, pty) :: tail
  | (vn, pt) :: tail                  -> (vn, pt) :: (add tail varnm pty)


let rec find (tyenv : t) (varnm : var_name) =
  match tyenv with
  | []                               -> raise Not_found
  | (vn, ts) :: tail when vn = varnm -> ts
  | (vn, ts) :: tail                 -> find tail varnm


let rec find_in_mono_type (tvid : Tyvarid.t) (ty : mono_type) =
  let iter      = find_in_mono_type tvid in
  let iter_list = find_in_mono_type_list tvid in
(*  let iter_poly = find_in_poly_type tvid in *)
  let (_, tymain) = ty in
    match tymain with
    | TypeVariable(tvref) ->
        begin
          match !tvref with
          | Link(tyl)   -> iter tyl
          | Free(tvidx) -> Tyvarid.eq tvidx tvid
          | Bound(_)    -> false
        end
    | FuncType(tydom, tycod)         -> (iter tydom) || (iter tycod)
    | ListType(tycont)               -> iter tycont
    | RefType(tycont)                -> iter tycont
    | ProductType(tylist)            -> iter_list tylist
    | VariantType(tylist, _)         -> iter_list tylist
(*    | TypeSynonym(tylist, _, pty)    -> (iter_list tylist) || (iter_poly pty) *)
    | _                              -> false


and find_in_poly_type (tvid : Tyvarid.t) ((Poly(ty)) : poly_type) =
  find_in_mono_type tvid ty


and find_in_mono_type_list (tvid : Tyvarid.t) (tystrlst : mono_type list) =
  List.fold_left (fun b tystr -> b || find_in_mono_type tvid tystr) false tystrlst


let rec find_in_type_environment (tvid : Tyvarid.t) (tyenv : t) =
  List.fold_left (fun b (_, pty) -> b || find_in_poly_type tvid pty) false tyenv

(*
let quantifiable_unbound_id_list : (type_variable_info ref) list ref = ref []


let rec listup_quantifiable_unbound_id ((_, tymain) : mono_type) (tyenv : t) : unit =
  let iter = (fun ty -> listup_quantifiable_unbound_id ty tyenv) in
    match tymain with
    | TypeVariable(tvref)             ->
        begin
          match !tvref with
          | Link(ty)   -> iter ty
          | Free(tvid) ->
              if Tyvarid.is_quantifiable tvid then
                if find_in_type_environment tvid tyenv then () else (* computation bottleneck *)
                  if List.mem tvref !quantifiable_unbound_id_list then () else
                    quantifiable_unbound_id_list := tvref :: !quantifiable_unbound_id_list
              else
                ()
          | Bound(_) -> ()
        end
(*    | TypeSynonym(tylist, _, tycont) -> List.iter iter tylist (* doubtful implementation *) *)
    | FuncType(tydom, tycod)         -> begin iter tydom ; iter tycod end
    | ProductType(tylist)            -> List.iter iter tylist
    | RecordType(asc)                -> List.iter iter (List.map (fun (fldnm, tystr) -> tystr) (Assoc.to_list asc))
    | VariantType(tylist, _)         -> List.iter iter tylist
    | ListType(tycont)               -> iter tycont
    | RefType(tycont)                -> iter tycont
    | ( IntType | BoolType | UnitType | StringType ) -> ()


let rec add_forall_struct (lst : (type_variable_info ref) list) (ty : mono_type) =
  match lst with
  | []            -> Mono(ty)
  | tvref :: tail ->
      match !tvref with
      | Free(tvid) ->
          let bid = Boundid.fresh (Tyvarid.get_kind tvid) () in
          begin
            tvref := Bound(bid) ;
            Forall(bid, add_forall_struct tail ty)
          end
      | ( Bound(_) | Link(_) ) -> assert false
*)


let generalize (ty : mono_type) (tyenv_before : t) =
  let rec iter (rng, tymain) =
    match tymain with
    | TypeVariable(tvref) ->
        begin
          match !tvref with
          | Link(tyl)  -> iter tyl
          | Bound(_)   -> ty
          | Free(tvid) ->
              if Tyvarid.is_quantifiable tvid then
                if find_in_type_environment tvid tyenv_before then ty else
                  let bid = Boundid.fresh (Tyvarid.get_kind tvid) () in
                  begin
                    tvref := Bound(bid) ;
                    ty
                  end
              else
                ty
        end
    | FuncType(tydom, tycod)    -> (rng, FuncType(iter tydom, iter tycod))
    | ProductType(tylist)       -> (rng, ProductType(List.map iter tylist))
    | RecordType(asc)           -> (rng, RecordType(Assoc.map_value iter asc))
    | VariantType(tylist, tyid) -> (rng, VariantType(List.map iter tylist, tyid))
    | ListType(tysub)           -> (rng, ListType(iter tysub))
    | RefType(tysub)            -> (rng, RefType(iter tysub))
    | ( UnitType
      | IntType
      | BoolType
      | StringType ) -> ty
  in
    Poly(iter ty)


let string_of_type_environment (tyenv : t) (msg : string) =
  let rec iter (tyenv : t) =
    match tyenv with
    | []               -> ""
    | (vn, ts) :: tail ->
            "    #  "
              ^ ( let len = String.length vn in if len >= 16 then vn else vn ^ (String.make (16 - len) ' ') )
       ^ " : " ^ ((* string_of_mono_type ts *) "type") ^ "\n"
              ^ (iter tail)
  in
      "    #==== " ^ msg ^ " " ^ (String.make (58 - (String.length msg)) '=') ^ "\n"
    ^ (iter tyenv)
    ^ "    #================================================================\n"


let string_of_control_sequence_type (tyenv : t) =
  let rec iter (tyenv : t) =
    match tyenv with
    | []               -> ""
    | (vn, ts) :: tail ->
        ( match String.sub vn 0 1 with
          | "\\" ->
              "    #  "
                ^ ( let len = String.length vn in if len >= 16 then vn else vn ^ (String.make (16 - len) ' ') )
                ^ " : " ^ ((* string_of_mono_type ts *) "type") ^ "\n" (* remains to be implemented *)
          | _    -> ""
        ) ^ (iter tail)
  in
      "    #================================================================\n"
    ^ (iter tyenv)
    ^ "    #================================================================\n"



let rec find_id_in_list (elm : Tyvarid.t) (lst : (Tyvarid.t * mono_type) list) =
  match lst with
  | []                                              -> raise Not_found
  | (tvid, tystr) :: tail  when Tyvarid.eq tvid elm -> tystr
  | _ :: tail                                       -> find_id_in_list elm tail

(*
let rec replace_id (lst : (Tyvarid.t * mono_type) list) (tystr : mono_type) =
  let iter = replace_id lst in
  let (rng, tymain) = tystr in
    match tymain with
    | TypeVariable(tvid)                   ->
        begin
          try find_id_in_list tvid lst with
          | Not_found -> (rng, TypeVariable(tvid))
        end
    | ListType(tycont)                     -> (rng, ListType(iter tycont))
    | RefType(tycont)                      -> (rng, RefType(iter tycont))
    | ProductType(tylist)                  -> (rng, ProductType(List.map iter tylist))
    | FuncType(tydom, tycod)               -> (rng, FuncType(iter tydom, iter tycod))
    | VariantType(tylist, varntnm)         -> (rng, VariantType(List.map iter tylist, varntnm))
    | TypeSynonym(tylist, tysynnm, pty)    -> (rng, TypeSynonym(List.map iter tylist, tysynnm, pty (* temporary *)))
    | other                                -> (rng, other)
*)

(*
let rec replace_id_poly (lst : (Tyvarid.t * mono_type) list) (pty : poly_type) =
  match pty with
  | Mono(ty)                 -> Mono(replace_id lst ty)
  | Forall(tvid, kd, ptysub) ->
      begin
        try
          let _ = find_id_in_list tvid lst in
            Forall(tvid, kd, ptysub) (* temporary *)
        with
        | Not_found -> Forall(tvid, kd, replace_id_poly lst ptysub)
      end
*)

let rec make_unquantifiable ((_, tymain) : mono_type) =
  let iter = make_unquantifiable in
    match tymain with
    | TypeVariable(tvref) ->
        begin
          match !tvref with
          | Link(tyl)  -> iter tyl
          | Free(tvid) -> ( tvref := Free(Tyvarid.set_quantifiability Unquantifiable tvid) )
          | Bound(bid) -> assert false
        end
    | ListType(tycont)                     -> iter tycont
    | RefType(tycont)                      -> iter tycont
    | ProductType(tylist)                  -> List.iter iter tylist
    | FuncType(tydom, tycod)               -> begin iter tydom ; iter tycod end
    | VariantType(tylist, varntnm)         -> List.iter iter tylist
(*    | TypeSynonym(tylist, tysynnm, pty)    -> begin List.iter iter tylist ; () (* temporary *) end *)
    | RecordType(asc)                      -> Assoc.iter_value iter asc
    | other                                -> ()

