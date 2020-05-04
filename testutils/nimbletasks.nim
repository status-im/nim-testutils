template addTestutilsTasks* =
  task moduleTests, "Run all module tests":
    let (files, errCode) = gorgeEx("git grep -l 'tests:'")
    echo files

