module Pughs.Run
  ( run
  ) where

import Control.Monad.Trans.Except (runExceptT)
import Data.Bifunctor (first)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Text.Lazy.IO qualified as TL
import Pughs.Build qualified as Build
import Pughs.Command qualified as Command
import Pughs.Evaluate qualified as Evaluate
import Pughs.Parse qualified as Parse
import Pughs.Render qualified as Render
import Pughs.Syntax qualified as Syntax
import Text.Megaparsec hiding (parse)
import Text.Pretty.Simple (pShowNoColor)

--------------------------------------------------------------------------------
run :: Command.Command -> IO ()
run (Command.Build srcDir renderMode distDir) = Build.buildDir srcDir renderMode distDir
run (Command.CommandWithPath path pmode (Command.Render Command.RenderNormal)) = do
  evaluated <- evaluateWithMode path pmode
  case evaluated of
    Left (Evaluate.PreProcessParseError err) -> T.putStrLn . T.pack $ errorBundlePretty err
    Left err -> TL.putStrLn $ pShowNoColor err
    Right nodes -> TL.putStrLn . Render.renderHtmls $ Render.pugNodesToHtml nodes
run (Command.CommandWithPath path pmode (Command.Render Command.RenderPretty)) = do
  evaluated <- evaluateWithMode path pmode
  case evaluated of
    Left (Evaluate.PreProcessParseError err) -> T.putStrLn . T.pack $ errorBundlePretty err
    Left err -> TL.putStrLn $ pShowNoColor err
    Right nodes -> T.putStr . Render.prettyHtmls $ Render.pugNodesToHtml nodes
run (Command.CommandWithPath path pmode Command.Evaluate) = do
  evaluated <- evaluateWithMode path pmode
  case evaluated of
    Left (Evaluate.PreProcessParseError err) ->
      T.putStrLn . Parse.parseErrorPretty $ err
    Left err -> TL.putStrLn $ pShowNoColor err
    Right nodes -> do
      TL.putStrLn $ pShowNoColor nodes
run (Command.CommandWithPath path pmode Command.Parse) = do
  parsed <- parseWithMode path pmode
  case parsed of
    Left (Evaluate.PreProcessParseError err) ->
      T.putStrLn . Parse.parseErrorPretty $ err
    Left err -> TL.putStrLn $ pShowNoColor err
    Right nodes -> TL.putStrLn $ pShowNoColor nodes
run (Command.CommandWithPath path pmode Command.Classes) = do
  parsed <- parseWithMode path pmode
  case parsed of
    Left err -> TL.putStrLn $ pShowNoColor err
    Right nodes -> mapM_ T.putStrLn $ Syntax.extractClasses nodes
run (Command.CommandWithPath path pmode (Command.Mixins mname)) = do
  parsed <- parseWithMode path pmode
  case parsed of
    Left err -> TL.putStrLn $ pShowNoColor err
    Right nodes -> do
      let ms = Syntax.extractMixins nodes
      case mname of
        Just name -> case Syntax.findMixin name ms of
          Just m -> TL.putStrLn $ pShowNoColor m
          Nothing -> putStrLn "No such mixin."
        Nothing -> TL.putStrLn $ pShowNoColor ms

--------------------------------------------------------------------------------
parseWithMode
  :: FilePath
  -> Command.ParseMode
  -> IO (Either Evaluate.PreProcessError [Syntax.PugNode])
parseWithMode path pmode =
  case pmode of
    Command.ParseShallow -> first Evaluate.PreProcessParseError <$> Parse.parsePugFile path
    Command.ParseDeep -> Evaluate.preProcessPugFile path

evaluateWithMode
  :: FilePath
  -> Command.ParseMode
  -> IO (Either Evaluate.PreProcessError [Syntax.PugNode])
evaluateWithMode path pmode = do
  parsed <- parseWithMode path pmode
  case parsed of
    Left err -> pure $ Left err
    Right nodes -> do
      evaluated <- runExceptT $ Evaluate.evaluate Evaluate.defaultEnv ["toplevel"] nodes
      pure evaluated
