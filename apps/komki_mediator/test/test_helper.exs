# Tests mit dem macOS-Dateiflag uappnd (Ticket #139) brauchen /usr/bin/chflags;
# auf der Linux-CI gibt es das nicht.
exclude = if File.exists?("/usr/bin/chflags"), do: [], else: [:chflags]
ExUnit.start(exclude: exclude)
