module Main exposing (..)

import Basics exposing (..)
import ElmTest exposing (..)
import Pouchdb exposing (..)
import Json.Encode exposing (object, string, Value)
import Task exposing (Task,perform)
import Html exposing (..)
import Html.App as Html
import Date exposing (..)

type alias TaskTest = { id: String
                      , description : String
                      , task: Task.Task DBError DBSuccess
                      , result : Maybe TaskResult}

updateAt : Int-> (a -> a) -> List a -> List a
updateAt index fun list =
  case index > 0 of
    True->
      let
        h = List.take (index-1) list
        t = List.drop (index-1) list
        t2 = List.drop 1 t
        element = case (List.head t) of
                    Just e -> [fun e]
                    _ -> []
      in
        List.append h (List.append element t2)
    _-> list

nth : Int -> List a -> Maybe a
nth index list =
  case index > 0 of
    True->
      let
        t = List.drop (index-1) list
      in
        List.head t
    _-> Nothing

performNth : Int -> Model -> Cmd Message
performNth index model =
   case nth index model.tasks of
          Just t -> Task.perform (Error index) (Success index) t.task
          Nothing -> Cmd.none
        

init : (Model, Cmd Message)
init =
  let
    model = initialModel
    x = performNth 1 model
  in 
    (model, x)

type DBSuccess = Put Pouchdb.SuccessPut
               | Get Pouchdb.SuccessGet
               | Remove Pouchdb.SuccessRemove
               | Destroy Pouchdb.SuccessDestroy
                 
type DBError = ErrPut Pouchdb.FailPut
             | ErrGet Pouchdb.FailGet
             | ErrRemove Pouchdb.FailRemove
             | ErrDestroy Pouchdb.FailDestroy
               
type TaskResult = Ok DBSuccess
                | Err DBError
             
type Message = Success Int DBSuccess
             | Error Int DBError
             | Hello Date
             | Change Pouchdb.ChangeEvent

type alias Model =
  {
    tasks : List TaskTest
  , db : Pouchdb
  , date : Date
  , fail : Maybe DBError
  , list : List Value
  }

createPutTaskTest : String -> String -> Json.Encode.Value -> Pouchdb -> TaskTest
createPutTaskTest id description object db =
  createPutUpdateTaskTest id description object Maybe.Nothing db 

createPutUpdateTaskTest : String -> String -> Json.Encode.Value -> Maybe String -> Pouchdb -> TaskTest
createPutUpdateTaskTest id description object rev db =
  let
    task = (Pouchdb.put db object rev)
           |> Task.mapError ErrPut
           |> Task.map Put
  in
   TaskTest id description task Maybe.Nothing

   
createGetTaskTest : String -> String -> DocRequest -> Pouchdb -> TaskTest
createGetTaskTest id description req db =
  let
    task = (Pouchdb.get db req)
    task2 = Task.mapError ErrGet task
    task3 = Task.map Get task2
  in
   TaskTest id description task3 Maybe.Nothing

createDestroyTaskTest : String -> String -> Pouchdb -> TaskTest
createDestroyTaskTest id description db =
  let
    task = (Pouchdb.destroy db)
    task2 = Task.mapError ErrDestroy task
    task3 = Task.map Destroy task2
  in
   TaskTest id description task3 Maybe.Nothing

   
initTasks : Pouchdb -> List TaskTest
initTasks db =
  let
    list = [ createPutTaskTest
               "1"
               "Put simple doc"
               ( Json.Encode.object
                   [ ("_id",string "1518")
                   , ("val",string "hello")
                   ]
               )
               db
           , createPutTaskTest
               "2"
               "put simple doc"
               ( Json.Encode.object
                   [ ("_id",string "1718")
                   , ("val",string "hello")
                   ]
               )
               db
           , createGetTaskTest
               "3"
               "Get simple doc"
               (let req = Pouchdb.request "1718" in {req|revs=Just True})
               db
           -- , createDestroyTaskTest
           --     "3"
           --     "Get simple doc"
           --     db
           ]
  in
     list
          
initialModel : Model
initialModel =
  let
    db = Pouchdb.db "DB-Test"
  in 
    { tasks = initTasks db
    , db = db
    , date =Date.fromTime(0)
    , fail = Maybe.Nothing
    , list =[]}

updateTaskAt : Int->TaskResult->Model->Model
updateTaskAt index result model =
  let 
    updatedTasks = updateAt index (\x->{x | result = Just result}) model.tasks
  in
    {model|tasks=updatedTasks}
  
update : Message -> Model -> (Model, Cmd Message)
update msg model =
  case msg of
    Hello date  ->
      let 
        updatedModel = {model | date = date}
      in
        (updatedModel, Cmd.none)
    Success index something ->
      let
        updatedModel = updateTaskAt index (Ok something) model
        newCmd = performNth (index + 1) model
      in
        (updatedModel, newCmd)
    Error index something ->
      let
        updatedModel = updateTaskAt index (Err something) model
        newCmd = performNth (index + 1) model
      in
        (updatedModel, newCmd)
    Change changeMsg ->
      let 
        updatedList = case changeMsg of
                        Changed val -> val::model.list
                        Completed val -> val::model.list
                        Pouchdb.Error val -> val::model.list
      in 
        ({model|list=updatedList}, Cmd.none)
  
view : Model -> Html Message
view model =
  div
    [ ]
    [ text "Testing PouchDB with el"
    , text (toString (year model.date))
    , viewTasks model
    , viewChanges model]

viewTasks model =
  div
    []
    (List.map viewTask model.tasks)

viewTask task =
  div
    []
    [ span [][text (task.id)]
    , span [][text (task.description)]
    , span [][text (toString task.result)]]


viewChanges model =
  div
    []
    (List.map viewChange model.list)
  
viewChange change =
  div
    []
    [text (toString change)]
  

subscriptions : Model -> Sub Message
subscriptions model =
  change "1" model.db { live = True
                      , include_docs = True
                      , include_conflicts = True
                      , attachments = False
                      , descending  = False
                      , since = Now
                      , limit  = Nothing } Change

main =  
  Html.program
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }