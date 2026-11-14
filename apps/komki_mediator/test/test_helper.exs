# Tests mit dem macOS-Dateiflag uappnd (Ticket #139) brauchen /usr/bin/chflags;
# auf der Linux-CI gibt es das nicht. Der Relay-Test (Ticket #143) braucht node.
exclude =
  if(File.exists?("/usr/bin/chflags"), do: [], else: [:chflags]) ++
    if System.find_executable("node"), do: [], else: [:node]

ExUnit.start(exclude: exclude)
