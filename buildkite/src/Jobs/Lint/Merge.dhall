let Prelude = ../../External/Prelude.dhall
let B = ../../External/Buildkite.dhall

let SelectFiles = ../../Lib/SelectFiles.dhall

let Pipeline = ../../Pipeline/Dsl.dhall
let JobSpec = ../../Pipeline/JobSpec.dhall

let Cmd = ../../Lib/Cmds.dhall
let Command = ../../Command/Base.dhall
let Docker = ../../Command/Docker/Type.dhall
let Size = ../../Command/Size.dhall

let B/SoftFail = B.definitions/commandStep/properties/soft_fail/Type

in

Pipeline.build
  Pipeline.Config::{
    spec = JobSpec::{
      dirtyWhen = [ SelectFiles.everything ],
      path = "Lint",
      name = "Merge"
    },
    steps = [
      Command.build
        Command.Config::{
          commands = [ Cmd.run "buildkite/scripts/merges-cleanly.sh compatible"]
          , label = "Check merges cleanly into compatible"
          , soft_fail = Some (B/SoftFail.Boolean True)
          , key = "clean-merge-compatible"
          , target = Size.Small
          , docker = Some Docker::{
              image = (../../Constants/ContainerImages.dhall).toolchainBase
            }
        },
      Command.build
        Command.Config::{
          commands = [ Cmd.run "buildkite/scripts/merges-cleanly.sh develop"]
          , label = "Check merges cleanly into develop"
          , key = "clean-merge-develop"
          , target = Size.Small
          , docker = Some Docker::{
              image = (../../Constants/ContainerImages.dhall).toolchainBase
            }
        }
    ]
  }
