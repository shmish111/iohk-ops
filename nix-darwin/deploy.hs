#! /usr/bin/env nix-shell
#! nix-shell -i runhaskell
{-# LANGUAGE OverloadedStrings, LambdaCase #-}

import Prelude hiding (FilePath)
import Turtle
import Data.Text (Text)
import qualified Data.Text as T
import qualified Filesystem.Path.CurrentOS as FP
import qualified System.Process as P

main :: IO ()
main = do
  (roleFile, hosts) <- options "Set up nix-darwin with a configuration." parser
  sh $ deployHosts roleFile hosts

parser :: Parser (FilePath, [Text])
parser = (,) <$> role <*> hosts
  where
    role = optPath "role" 'r' "Role nix file"
    hosts = some (argText "HOSTS..." "Target machines to SSH into")

deployHosts :: FilePath -> [Text] -> Shell ()
deployHosts roleFile hosts = do
  (drv, outPath) <- instantiateNixDarwin roleFile
  mapM_ (deployHost drv outPath) hosts

deployHost :: FilePath -> FilePath -> Text -> Shell ExitCode
deployHost drv outPath host = do
  printf ("Copying derivation to "%s%"\n") host
  procs "nix-copy-closure" ["--to", host, tt drv] empty
  printf ("Building derivation on "%s%"\n") host
  procs "ssh" [host, "NIX_REMOTE=daemon", "nix-store", "-r", tt drv, "-j", "1"] empty
  currentSystem <- T.stripEnd . snd <$> procStrict "ssh" [host, "readlink", "/run/current-system"] empty

  if currentSystem == tt outPath
    then do
      printf ("Already deployed to "%s%"\n") host
      pure ExitSuccess
    else do
      printf ("Activating on "%s%"\n") host
      -- using system instead of procs so that ssh can pass tty to sudo
      let
        args = ["-t", host, "sudo", "NIX_REMOTE=daemon", tt (outPath </> "activate")]
        activate = P.proc "ssh" (map T.unpack args)
      system activate empty

-- | Get the derivation of the nix-darwin system, and its output path,
-- but don't build.
instantiateNixDarwin :: FilePath -> Shell (FilePath, FilePath)
instantiateNixDarwin configuration = do
  drv <- inproc "nix-instantiate" [ "--show-trace", "./lib/build.nix", "-A", "system"
                                  , "--arg", "configuration", tt configuration ] empty
  outPath <- inproc "nix-store" ["-q", "--outputs", format l drv] empty & limit 1
  pure (lineToFilePath drv, lineToFilePath outPath)

lineToFilePath :: Line -> FilePath
lineToFilePath = FP.fromText . lineToText

tt :: FilePath -> Text
tt = format fp
