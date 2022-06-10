"""Declare runtime dependencies

These are needed for local dev, and users must install them as well.
See https://docs.bazel.build/versions/main/skylark/deploying.html#dependencies
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//ts/private:versions.bzl", TS_VERSIONS = "VERSIONS")

versions = struct(
    bazel_lib = "0.12.1",
    rules_nodejs = "5.4.0",
)

worker_versions = struct(
    bazel_worker_version = "5.4.2",
    bazel_worker_integrity = "sha512-wQZ1ybgiCPkuITaiPfh91zB/lBYqBglf1XYh9hJZCQnWZ+oz9krCnZcywI/i1U9/E9p3A+4Y1ni5akAwTMmfUA==",
    google_protobuf_version = "3.20.1",
    google_protobuf_integrity = "sha512-XMf1+O32FjYIV3CYu6Tuh5PNbfNEU5Xu22X+Xkdb/DUexFlCzhvv7d5Iirm4AOwn8lv4al1YvIhzGrg2j9Zfzw==",
)

LATEST_VERSION = TS_VERSIONS.keys()[-1]

def _http_archive_version_impl(rctx):
    if rctx.attr.version:
        version = rctx.attr.version
    else:
        json_path = rctx.path(rctx.attr.version_from)
        p = json.decode(rctx.read(json_path))
        if "devDependencies" in p.keys() and "typescript" in p["devDependencies"]:
            ts = p["devDependencies"]["typescript"]
        elif "dependencies" in p.keys() and "typescript" in p["dependencies"]:
            ts = p["dependencies"]["typescript"]
        else:
            fail("key `typescript` not found in either dependencies or devDependencies of %s" % json_path)
        if any([not seg.isdigit() for seg in ts.split(".")]):
            fail("""typescript version in package.json must be exactly specified, not a semver range: %s.
            You can supply an exact `ts_version` attribute to `rules_ts_dependencies` to bypass this check.""" % ts)
        version = ts

    if rctx.attr.integrity:
        integrity = rctx.attr.integrity
    elif version in TS_VERSIONS.keys():
        integrity = TS_VERSIONS[version]
    else:
        fail("""typescript version {} is not mirrored in rules_ts, is this a real version?
            If so, you must manually set `ts_integrity`.
            See documentation on rules_ts_dependencies.""".format(version))

    rctx.download_and_extract(
        url = [u.format(version) for u in rctx.attr.urls],
        integrity = integrity,
    )
    build_file_substitutions = {"ts_version": version}
    build_file_substitutions.update(**rctx.attr.build_file_substitutions)
    rctx.template(
        "BUILD.bazel",
        rctx.path(rctx.attr.build_file),
        substitutions = build_file_substitutions,
        executable = False,
    )

http_archive_version = repository_rule(
    doc = "Re-implementation of http_archive that can read the version from package.json",
    implementation = _http_archive_version_impl,
    attrs = {
        "integrity": attr.string(doc = "Needed only if the ts version isn't mirrored in `versions.bzl`."),
        "version": attr.string(doc = "Explicit version for `urls` placeholder. If provided, the package.json is not read."),
        "urls": attr.string_list(doc = "URLs to fetch from. Each must have one `{}`-style placeholder."),
        "build_file": attr.label(doc = "The BUILD file to write into the created repository."),
        "build_file_substitutions": attr.string_dict(doc = "Substitutions to make when expanding the BUILD file."),
        "version_from": attr.label(doc = "Location of package.json which may have a version for the package."),
    },
)

# WARNING: any additions to this function may be BREAKING CHANGES for users
# because we'll fetch a dependency which may be different from one that
# they were previously fetching later in their WORKSPACE setup, and now
# ours took precedence. Such breakages are challenging for users, so any
# changes in this function should be marked as BREAKING in the commit message
# and released only in semver majors.
def rules_ts_dependencies(ts_version_from = None, ts_version = None, ts_integrity = None):
    """Dependencies needed by users of rules_ts.

    To skip fetching the typescript package, define repository called 'npm_typescript' before calling this.

    Args:
        ts_version_from: label of a json file (typically `package.json`) which declares an exact typescript version
            in a dependencies or devDependencies property.
            Exactly one of `ts_version` or `ts_version_from` must be set.
        ts_version: version of the TypeScript compiler.
            Exactly one of `ts_version` or `ts_version_from` must be set.
        ts_integrity: integrity hash for the npm package.
            By default, uses values mirrored into rules_ts.
            For example, to get the integrity of version 4.6.3 you could run
            `curl --silent https://registry.npmjs.org/typescript/4.6.3 | jq -r '.dist.integrity'`
    """

    if (ts_version and ts_version_from) or (not ts_version_from and not ts_version):
        fail("""Exactly one of `ts_version` or `ts_version_from` must be set.""")

    # The minimal version of bazel_skylib we require
    maybe(
        http_archive,
        name = "bazel_skylib",
        sha256 = "c6966ec828da198c5d9adbaa94c05e3a1c7f21bd012a0b29ba8ddbccb2c93b0d",
        urls = [
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.1.1/bazel-skylib-1.1.1.tar.gz",
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.1.1/bazel-skylib-1.1.1.tar.gz",
        ],
    )

    maybe(
        http_archive,
        name = "rules_nodejs",
        sha256 = "1f9fca05f4643d15323c2dee12bd5581351873d45457f679f84d0fe0da6839b7",
        urls = ["https://github.com/bazelbuild/rules_nodejs/releases/download/{0}/rules_nodejs-core-{0}.tar.gz".format(versions.rules_nodejs)],
    )

    maybe(
        http_archive,
        name = "aspect_rules_js",
        sha256 = "6b218d2ab2e365807d1d403580b2c865a771e7fda9449171b2abd9765d0299b3",
        strip_prefix = "rules_js-0.12.1",
        url = "https://github.com/aspect-build/rules_js/archive/refs/tags/v0.12.1.tar.gz",
    )

    maybe(
        http_archive,
        name = "aspect_bazel_lib",
        sha256 = "91aa7356b22ecdb87dcf5f1cc8a6a147e23a1ef425221bab75e5f857cd6b2716",
        strip_prefix = "bazel-lib-" + versions.bazel_lib,
        url = "https://github.com/aspect-build/bazel-lib/archive/refs/tags/v{}.tar.gz".format(versions.bazel_lib),
    )

    maybe(
        http_archive,
        name = "npm_google_protobuf",
        build_file = "@aspect_rules_ts//ts:BUILD.package",
        integrity = worker_versions.google_protobuf_integrity,
        urls = ["https://registry.npmjs.org/google-protobuf/-/google-protobuf-{}.tgz".format(worker_versions.google_protobuf_version)],
    )

    maybe(
        http_archive,
        name = "npm_at_bazel_worker",
        integrity = worker_versions.bazel_worker_integrity,
        build_file = "@aspect_rules_ts//ts:BUILD.package",
        urls = ["https://registry.npmjs.org/@bazel/worker/-/worker-{}.tgz".format(worker_versions.bazel_worker_version)],
    )

    maybe(
        http_archive_version,
        name = "npm_typescript",
        version = ts_version,
        version_from = ts_version_from,
        integrity = ts_integrity,
        build_file = "@aspect_rules_ts//ts:BUILD.typescript",
        build_file_substitutions = {
            "bazel_worker_version": worker_versions.bazel_worker_version,
            "google_protobuf_version": worker_versions.google_protobuf_version,
        },
        urls = ["https://registry.npmjs.org/typescript/-/typescript-{}.tgz"],
    )
