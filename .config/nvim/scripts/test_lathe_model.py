"""Run with python3 scripts/test_lathe_model.py."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("lathe_model", Path(__file__).with_name("lathe-model.py"))
lathe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lathe)


class MissingDependencyTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        lathe.SHARED_REPO = Path(scratch.name) / "maven"
        self.repositories = (Path.home() / ".m2/repository", lathe.SHARED_REPO)

    def test_missing_jar_tracks_jar_and_pom_in_both_caches(self):
        coordinate, paths = lathe.missing_dependencies(
            "[INFO] Building example:app:jar:1\n"
            "[WARNING] The POM for example.libs:backend:jar:1.2.3 is missing, no dependency information available\n"
            "[ERROR] dependency: example.libs:backend:jar:1.2.3 (compile)\n"
        )
        self.assertEqual(coordinate, "example.libs:backend:1.2.3")
        self.assertEqual(paths, {
            str(repository / f"example/libs/backend/1.2.3/backend-1.2.3.{extension}")
            for repository in self.repositories for extension in ("jar", "pom")
        })

    def test_missing_classified_jar_watches_unclassified_pom(self):
        coordinate, paths = lathe.missing_dependencies(
            "[ERROR] Could not find artifact example.libs:backend:jar:tests:2.0-SNAPSHOT in local\n"
        )
        self.assertEqual(coordinate, "example.libs:backend:2.0-SNAPSHOT")
        self.assertEqual(paths, {
            str(repository / "example/libs/backend/2.0-SNAPSHOT" / name)
            for repository in self.repositories
            for name in ("backend-2.0-SNAPSHOT-tests.jar", "backend-2.0-SNAPSHOT.pom")
        })

    def test_compilation_failure_does_not_report_missing_artifact(self):
        self.assertEqual(lathe.missing_dependencies(
            "[WARNING] The POM for example:backend:jar:1.0 is missing, no dependency information available\n"
            "[ERROR] Failed to execute goal example:compiler:maven-plugin:1.0 on project example:app:jar:1:\n"
            "[ERROR] cannot find symbol\n"
        ), (None, set()))

    def test_missing_parent_does_not_watch_a_jar(self):
        coordinate, paths = lathe.missing_dependencies(
            "[ERROR] Non-resolvable parent POM: example.libs:parent:pom:1.0 (absent)\n"
        )
        self.assertEqual(coordinate, "example.libs:parent:1.0")
        self.assertEqual(paths, {
            str(repository / "example/libs/parent/1.0/parent-1.0.pom") for repository in self.repositories
        })


if __name__ == "__main__":
    unittest.main()
