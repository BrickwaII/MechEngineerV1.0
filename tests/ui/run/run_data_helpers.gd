extends RefCounted
## Shared by the run data tests: a scratch runs folder per suite, removed
## after each test.


## Deletes `path` and everything in it.
static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)


## The only run folder under `root`, or "" when there is not exactly one.
static func only_run(root: String) -> String:
	var dirs := DirAccess.get_directories_at(root)
	return root.path_join(dirs[0]) if dirs.size() == 1 else ""
