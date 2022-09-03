{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-incomplete-patterns #-}

module Vloader where

import Control.Exception (try)
import Data.List (foldl', intercalate, isSuffixOf)
import Data.String (IsString (fromString))
import Data.Text (Text, pack, replace, splitOn, stripSuffix, unpack)
import Data.Text.Lazy (toStrict)
import Data.Yaml (FromJSON (parseJSON), ParseException, Value (Object), YamlException, decode, decodeFileEither, prettyPrintParseException, (.:))
import GHC.Base (IO (IO))
import GHC.Generics (Datatype (moduleName))
import GHC.IO.Exception (IOException (IOError))
import GHC.TypeLits (ErrorMessage)
import Options.Applicative (Parser, ParserInfo, fullDesc, header, help, helper, info, long, metavar, progDesc, short, strOption, switch, value, (<**>))
import System.Directory (getDirectoryContents, getHomeDirectory)
import System.Exit (exitSuccess)
import System.FilePath ()
import System.IO ()
import Text.Termcolor (format)
import qualified Text.Termcolor.Foreground as F
import Text.Termcolor.Style (bold)
import Vbanner (vModBanner)

data ModConfig = ModConfig
  { modPath :: String,
    resFile :: String,
    modules :: [String]
  }
  deriving (Eq)

type ModName = String

instance FromJSON ModConfig where
  parseJSON (Object o) =
    ModConfig
      <$> o .: "mod_path"
      <*> o .: "res_file"
      <*> o .: "modules"
  parseJSON _ = error "Error Parsing Config file "

data Config = Config
  { confFile :: String,
    version :: Bool,
    quiet :: Bool
  }
  deriving (Eq)

config :: Parser Config
config =
  Config
    <$> strOption
      ( long "cfg"
          <> short 'f'
          <> value "~/.config/vmod/vmod.yml"
          <> metavar "CFG_FILE"
          <> help "Provide full path to the config file"
      )
    <*> switch
      ( long "version"
          <> short 'v'
          <> help "Display Vmod version"
      )
    <*> switch
      ( long "quiet"
          <> short 'q'
          <> help "Doesnot display Banner"
      )

getOpts :: ParserInfo Config
getOpts =
  info
    (config <**> helper)
    ( fullDesc
        <> progDesc "VmodLoader is used to bundle lua modules"
        <> header "V Mod Loader -Lua Module Bundler"
    )

border :: [Char]
border = concat $ replicate 30 "="

getMods :: FilePath -> String -> IO String
getMods modPath modName = do
  let modPrefix = getModPrefix modPath
  dirFiles <- try . getDirectoryContents $ modPath ++ "/" ++ modName :: IO (Either IOError [FilePath])
  case dirFiles of
    Right mods -> return $modGen modPrefix modName mods
    Left err -> "" <$ (putStrLn . format . bold . F.red . read $("\nError parsing Module : " ++ modName ++ "\n>> [Error]: " ++ show err ++ "\n"))

modGen :: String -> String -> [FilePath] -> String
modGen modPrefix modN dirFiles =
  let modFiles = filter (isSuffixOf ".lua") dirFiles
      (modHead, modName) = sanitizeMod modPrefix modN
      header = ["-- " ++ border, "--    MOD : " ++ modHead, "-- " ++ border]
      luaMods = map (\mod -> "require(\"" ++ modPrefix ++ modName ++ fromMaybeMod (sanitizeLua mod) ++ "\")") modFiles
      luaRes = header ++ luaMods
   in intercalate "\n" luaRes

writeMods :: [ModName] -> String -> IO ()
writeMods luaMods resFile =
  writeFile (resFile ++ ".lua") $intercalate "\n" $banner ++ luaMods
  where
    banner = ["-- " ++ border, "-- GENERATED BY V MOD LOADER : )", "-- " ++ border ++ "\n\n"]

getModPrefix :: FilePath -> String
getModPrefix modPath =
  let paths = map unpack $splitOn (pack "/") (pack modPath)
      fetchPrefix :: [String] -> Bool -> String
      fetchPrefix [] _ = ""
      fetchPrefix (x : xs) False
        | x == "lua" = fetchPrefix xs True
        | otherwise = fetchPrefix xs False
      fetchPrefix (x : xs) True = foldl' (\acc x -> acc ++ "." ++ x) x xs ++ "."
   in fetchPrefix paths False

getConfig :: FilePath -> IO ModConfig
getConfig confFile = do
  home <- getHomeDirectory
  file <- decodeFileEither (replaceHome home confFile) :: IO (Either ParseException ModConfig)
  case file of
    Left err -> error $ " ** Config Error.\n>> Ensure that the config is in the specified directory and the config format and indendation is correct\n\n [Error] : \n  >>" ++ prettyPrintParseException err
    Right modConf -> return modConf

sanitizeMod :: String -> String -> (String, String)
sanitizeMod modHead "." = (init modHead, "")
sanitizeMod _ modName = (modName, modName ++ ".")

sanitizePath :: ModConfig -> Maybe ModConfig
sanitizePath ModConfig {modPath, resFile, modules} =
  do
    let mdP
          | last modPath == '/' = init modPath
          | otherwise = modPath
        resF
          | ".lua" `isSuffixOf` resFile = sanitizeLua resFile
          | otherwise = Just resFile
    resF >>= (\res -> Just $ ModConfig mdP res modules)

sanitizeLua :: String -> Maybe ModName
sanitizeLua modFile = unpack <$> stripSuffix ".lua" (fromString modFile)

replaceHome :: FilePath -> FilePath -> FilePath
replaceHome home confPath =
  unpack $replace "~" homeFile confFile
  where
    [homeFile, confFile] = fromString <$> [home, confPath]

fromMaybeMod :: Maybe ModName -> ModName
fromMaybeMod = \case
  Just mod -> mod
  Nothing -> error "Unable to remove lua extension "

fromMaybeConfig :: Maybe ModConfig -> ModConfig
fromMaybeConfig = \case
  Just mod -> mod
  Nothing -> error "Unable to parse Config .Please Ensure that the config contains required fields\n"

getVersion :: Bool -> Bool -> IO ()
getVersion True q =
  do
    let version = "1.5.0"
    case q of
      False -> putStrLn $format . bold . F.cyan . read $ "\tVmod Version : " ++ version ++ "\n"
      True -> putStrLn version
    exitSuccess
getVersion False _ = return ()

getBanner :: Bool -> IO ()
getBanner False = putStrLn . format . bold $ read vModBanner
getBanner  _= return ()
