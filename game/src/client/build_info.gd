## Identity of this build (CI, roadmap X.02). The pipeline (.github/workflows/build.yml) replaces BUILD
## by the run number before exporting; 0 = a build from the project (editor, tests): never self-updates.
class_name BuildInfo
extends RefCounted

const BUILD := 0
## "owner/repo" of the GitHub repository whose latest release holds the newest client
const REPO := "meakitfed/SuperDofus"
