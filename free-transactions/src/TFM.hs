{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE GADTs #-}

module TFM where

import Debug.Trace

import Prelude hiding           (log)
import Control.Monad            (when)
import Control.Monad.IO.Class   (MonadIO, liftIO)
import Control.Monad.Except     (ExceptT(..), MonadTrans, lift)
import Control.Monad.Free
import Control.Monad.Free.TH    (makeFree, makeFreeCon)
import Control.Monad.Trans.Free (FreeT(..))
import Data.Text                (Text, pack)
import Data.HashMap             (Map, empty, insert, lookup)
import Data.Function            (id)
import Control.Monad.Except     (MonadError, runExceptT, catchError, throwError)
import Control.Exception        (IOException(..), SomeException(..), Exception, throw)
import Data.Typeable            (Typeable)
import Text.Read                (readMaybe)
import Data.Monoid              ((<>))
import Control.Monad.Trans.Maybe (runMaybeT)
import Data.Foldable            (msum)

type Key = Text
type Val = Text

data Err = Err deriving (Eq, Show)

--data TestF n where
--  Log      :: (MonadError Err m) => Text -> (m () -> n)         -> TestF n
--  Get      :: (MonadError Err m) => Key -> (m Val -> n)         -> TestF n
--  Put      :: (MonadError Err m) => Key -> Val -> (m () -> n)   -> TestF n
--  Rollback :: (MonadError Err m) => (m () -> n)                 -> TestF n
--  Commit   :: (MonadError Err m) => (m () -> n)                 -> TestF n
--  Transact :: (MonadError Err m) => TestFree m a -> (m a -> n)  -> TestF n

data TestF n where
  Log      :: (MonadError Err m) => Text -> (m () -> n)         -> TestF n
  Get      :: (MonadError Err m) => Key -> (m Val -> n)         -> TestF n
  Put      :: (MonadError Err m) => Key -> Val -> (m () -> n)   -> TestF n
  Rollback :: (MonadError Err m) => (m () -> n)                 -> TestF n
  Commit   :: (MonadError Err m) => (m () -> n)                 -> TestF n
--  Transact :: (MonadError Err m) => TestFree m a -> (m a -> n)  -> TestF n

instance Functor TestF where
  fmap f (Log msg n) = Log msg (f . n)
  fmap f (Get k n) = Get k (f . n)
  fmap f (Put k v n) = Put k v (f . n)
  fmap f (Rollback n) = Rollback (f . n)
  fmap f (Commit n) = Commit (f . n)
--  fmap f (Transact block n) = Transact block (f . n)

type TestFree m a = FreeT TestF m a
--  deriving (Applicative, Functor, Monad, MonadFree (TestF tex))

makeFree ''TestF

--log      :: (MonadFree TestF m) => Text -> m ()
--get      :: (MonadFree TestF m) => Key -> m Val
--put      :: (MonadFree TestF m) => Key -> Val -> m ()
--transact :: (MonadFree TestF m) => TestFree m a -> m a
--rollback :: (MonadFree TestF m) => m ()
--commit   :: (MonadFree TestF m) => m ()

-- either :: (a -> c) -> (b -> c) -> Either a b -> c
-- runExceptT :: ExceptT e m a -> m (Either e a)
err :: (MonadError Err m) => Either Err a -> m a
err = either throwError return

a :: (MonadFree TestF m, MonadError Err m) => Text -> m ()
a = undefined

someFn :: ExceptT Err IO ()
someFn = err (Left Err)

type TFM a = FreeT TransF (Either Err)

-- FreeT (f :: * -> *) (m :: * -> *) a
type TransFree = Free TransF

data TransF next where
  Output    :: String ->                  (Either Err () -> next) -> TransF next
  Input     :: Read a =>                  (Either Err a -> next)  -> TransF next
  Transact  :: Show a => ExceptT Err TransFree a -> (Either Err a -> next)  -> TransF next
  Reset     ::                            (Either Err () -> next) -> TransF next

instance Functor TransF where
  fmap f (Output s n) = Output s (f . n)
  fmap f (Input n) = Input (f . n)
  fmap f (Transact block n) = Transact block (f . n)
  fmap f (Reset n) = Reset (f . n)


makeFree ''TransF

-- runExceptT :: ExceptT e m a -> m (Either e a)

output1 :: MonadFree TransF m => String -> ExceptT Err m ()
output1 s = ExceptT $ liftF $ Output s id

input1 :: (MonadFree TransF m, Read a) => ExceptT Err m a
input1 = ExceptT $ liftF $ Input id

-- liftF :: (Functor f, MonadFree f m) => f a -> m a
-- liftF :: TransF (Either Err a) -> m (Either Err a)
-- Transact  :: Show a => ExceptT Err TransFree a -> (ExceptT Err TransFree a -> next) -> TransF next
-- transact1 :: MonadFree TransF m => TransFree ae -> m ae
transact1 :: (MonadFree TransF m, Show a) => ExceptT Err TransFree a -> m (Either Err a)
transact1 block = liftF $ Transact block id

unwrap :: ExceptT Err TransFree a -> a
unwrap exc = do
  let eth = runExceptT exc
  undefined
--f :: TransF (ExceptT Err TransFree a) -> m (Either Err a)
--f = liftF _

reset1 :: MonadFree TransF m => ExceptT Err m ()
reset1 = ExceptT $ liftF $ Reset id

main :: IO ()
main = do
  r <- fireIO test
  print r

test :: TransFree (Either Err ())
test = runExceptT $ do
  n <- transact1 $ do
    n <- input1
    when (n <= 0) $ do
      output1 "The number should be positive."
      reset1
    return $ Right n
  output1 $ "You've just entered " ++ show (n :: Either Err (Either Err Integer))

fireIO :: MonadIO m => TransFree a -> m a
fireIO = iterM runIO

runIO :: MonadIO m => TransF (m a) -> m a
runIO (Output s next) = do
  liftIO $ putStrLn s
  next $ Right ()
runIO (Input next) = do
  s <- liftIO getLine
  let eth = readE s
  next eth -- eth :: Either Err a
  where
    readE :: (Read a1) => String -> Either Err a1
    readE s = case readMaybe s of
      Just x -> Right x
      Nothing -> Left Err
runIO (Transact block next) = do
  -- eth :: Either Err a
  -- fireIO :: MonadIO m => TransFree a -> m a
  -- block :: ExceptT Err TransFree a
  -- runExceptT :: ExceptT e m a -> m (Either e a)
  -- runExceptT block :: Free TransF (Either Err a)
  -- runExceptT block :: TransFree (Either Err a)
  -- fireIO (runExceptT block) :: MonadIO m => m (Either Err a)
  eth <- fireIO $ runExceptT block
  traceShowM $ "----> " <> show eth
  case eth of
    Left err -> next $ Left err
    Right a -> next $ Right a
runIO (Reset next) = next $ Left Err

--foo :: (MonadFree TestF m, MonadError Err m) => m ()
--foo = do
--  x <- get "k1"
--  put "k2" x
--  throwError Err
--  z <- bar
--  log $ pack $ show z
--
--bar :: (MonadFree TestF m) => m Int
--bar = do
--  y <- get "k3"
--  log $ pack $ show y
--  when (y == "42")
--    rollback
--  put "k4" y
--  return (42 :: Int)

-- > {-# OPTIONS_GHC -Wall                      #-}
-- > {-# OPTIONS_GHC -fno-warn-name-shadowing   #-}
-- > {-# OPTIONS_GHC -fno-warn-type-defaults    #-}
-- > {-# OPTIONS_GHC -fno-warn-unused-do-bind   #-}
-- > {-# OPTIONS_GHC -fno-warn-missing-methods  #-}
-- > {-# OPTIONS_GHC -fno-warn-orphans          #-}

--log :: (MonadFree TestF m) => Text -> m ()
--log msg = liftF $ Log msg ()
--
--get :: (MonadFree TestF m) => Key -> m Val
--get k = liftF $ Get k id
--
--put :: (MonadFree TestF m) => Key -> Val -> m ()
--put k v = liftF $ Put k v ()
--
--transact :: (MonadFree TestF m) => TestFree a -> m a
--transact block = liftF $ Transact block id
--
--rollback :: (MonadFree TestF m) => m ()
--rollback = liftF $ Rollback ()
--
--commit :: (MonadFree TestF m) => m ()
--commit = liftF $ Commit ()
