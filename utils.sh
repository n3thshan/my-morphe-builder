#!/usr/bin/env bash

MODULE_TEMPLATE_DIR="module"
CWD=$(pwd)
TEMP_DIR="temp"
BIN_DIR="bin"
BUILD_DIR="build"
DL_SRCS=("direct" "archive" "apkmirror" "apkpure" "official")

if [ "${GITHUB_TOKEN-}" ]; then GH_HEADER="Authorization: token ${GITHUB_TOKEN}"; else GH_HEADER=; fi
NEXT_VER_CODE=${NEXT_VER_CODE:-$(date +'%Y%m%d')}
OS=$(uname -o)

toml_prep() {
	if [ ! -f "$1" ]; then return 1; fi
	if [ "${1##*.}" == toml ]; then
		__TOML__=$($TOML --output json --file "$1" .)
	elif [ "${1##*.}" == json ]; then
		__TOML__=$(cat "$1")
	else abort "config extension not supported"; fi
}
toml_get_table_names() { jq -r -e 'to_entries[] | select(.value | type == "object") | .key' <<<"$__TOML__"; }
toml_get_table_main() { jq -r -e 'to_entries | map(select(.value | type != "object")) | from_entries' <<<"$__TOML__"; }
toml_get_table() { jq -r -e ".\"${1}\"" <<<"$__TOML__"; }
toml_get() {
	local op quote_placeholder=$'\001'
	op=$(jq -r ".\"${2}\" | values" <<<"$1")
	if [ "$op" ]; then
		op="${op#"${op%%[![:space:]]*}"}"
		op="${op%"${op##*[![:space:]]}"}"
		op=${op//\\\'/$quote_placeholder}
		op=${op//"''"/$quote_placeholder}
		op=${op//"'"/'"'}
		op=${op//$quote_placeholder/$'\''}
		echo "$op"
	else return 1; fi
}

pr() { echo -e "\033[0;32m[+] ${1}\033[0m"; }
epr() {
	echo >&2 -e "\033[0;31m[-] ${1}\033[0m"
	if [ "${GITHUB_REPOSITORY-}" ]; then echo >&2 -e "::error::utils.sh [-] ${1}\n"; fi
}
wpr() {
	echo >&2 -e "\033[0;33m[!] ${1}\033[0m"
	if [ "${GITHUB_REPOSITORY-}" ]; then echo >&2 -e "::warning::utils.sh [!] ${1}\n"; fi
}

_clean_tmp() {
	rm -rf ./${TEMP_DIR}/*tmp.* ./${TEMP_DIR}/*tmp_* ./${TEMP_DIR}/*/*tmp.* ./${TEMP_DIR}/*-temporary-files ./*-temporary-files
}

abort() {
	epr "ABORT: ${1-}"
	_clean_tmp
	trap - SIGTERM SIGINT EXIT
	kill -9 -- -$$ 2>/dev/null
	exit 1
}
java() {
	if [ "${JAVA_HOME_21_X64-}" ]; then
		env -i JAVA_HOME="$JAVA_HOME_21_X64" "$JAVA_HOME_21_X64"/bin/java --enable-native-access=ALL-UNNAMED "$@"
	else
		env -i java --enable-native-access=ALL-UNNAMED "$@"
	fi
}

get_prebuilts() {
	local cli_src=$1 cli_ver=$2 patches_src=$3 patches_ver=$4
	pr "Getting prebuilts (${patches_src%/*})" >&2
	local cl_dir=${patches_src%/*}
	cl_dir=${TEMP_DIR}/${cl_dir,,}-rv
	[ -d "$cl_dir" ] || mkdir "$cl_dir"

	for src_ver in "Patches $patches_src $patches_ver" "CLI $cli_src $cli_ver"; do
		set -- $src_ver
		local tag=$1 src=$2 ver=${3-}

		local dir=${src%/*}
		dir=${TEMP_DIR}/${dir,,}-rv
		[ -d "$dir" ] || mkdir "$dir"

		local rv_rel="https://api.github.com/repos/${src}/releases" name_ver
		if [ "$ver" = "dev" ]; then
			local resp
			resp=$(gh_req "$rv_rel" -) || return 1
			ver=$(jq -e -r '.[] | .tag_name' <<<"$resp" | get_highest_ver) || return 1
		fi
		if [ "$ver" = "latest" ]; then
			rv_rel+="/latest"
			name_ver="*"
		else
			rv_rel+="/tags/${ver}"
			name_ver="$ver"
		fi

		local file
		if [ "$tag" = "CLI" ]; then
			file=$(find "$dir" -maxdepth 1 -name "*cli-${name_ver#v}*.jar" -o -name "*desktop-${name_ver#v}*.jar" -type f 2>/dev/null)
			local grab_cl="false"
		elif [ "$tag" = "Patches" ]; then
			file=$(find "$dir" -maxdepth 1 -name "*patches-${name_ver#v}.*" -type f 2>/dev/null)
			local grab_cl="true"
		else abort unreachable; fi

		local url tag_name matches
		if [ "$ver" = "latest" ]; then
			file=$(grep -v '/[^/]*dev[^/]*$' <<<"$file" | head -1)
		else
			file=$(grep "/[^/]*${ver#v}[^/]*\$" <<<"$file" | head -1)
		fi
		if [ -z "$file" ]; then
			local resp asset name digest
			resp=$(gh_req "$rv_rel" -) || return 1
			tag_name=$(jq -r '.tag_name // empty' <<<"$resp" 2>/dev/null) || return 1
			if [ "$tag" = "Patches" ]; then
				local picked
				if ! picked=$(pick_patch_bundle <<<"$resp") || [ -z "$picked" ]; then
					epr "No asset was found"
					return 1
				fi
				IFS=$'\t' read -r _ name digest <<<"$picked"
				url=$(jq -r --arg n "$name" '(.assets // [])[] | select(.name == $n) | .url' <<<"$resp" | head -1) || return 1
				if [ -z "$url" ]; then
					epr "No asset was found"
					return 1
				fi
			else
				matches=$(jq -e '.assets | map(select(.name | (endswith("asc") or endswith("json")) | not))' <<<"$resp") || return 1
				if [ "$(jq 'length' <<<"$matches")" -gt 1 ]; then
					local matches_new
					matches_new=$(jq -e -r 'map(select(.name | contains("-dev") | not))' <<<"$matches")
					if [ "$(jq 'length' <<<"$matches_new")" -eq 1 ]; then
						matches=$matches_new
					elif matches_mpp=$(jq -e -r 'map(select(.name | endswith(".mpp"))) | select(length >= 1)' <<<"$matches_new"); then
						# some patch releases ship extra files (e.g. SHA256SUMS.txt) next to the
						# bundle - always prefer the .mpp when more than one candidate remains
						matches=$matches_mpp
					fi
				fi
				if [ "$(jq 'length' <<<"$matches")" -eq 0 ]; then
					epr "No asset was found"
					return 1
				elif [ "$(jq 'length' <<<"$matches")" -ne 1 ]; then
					wpr "More than 1 asset was found for this release. Falling back to the first one found..."
				fi
				asset=$(jq -r ".[0]" <<<"$matches")
				url=$(jq -r .url <<<"$asset")
				name=$(jq -r .name <<<"$asset")
			fi

			file="${dir}/${name}"
			gh_dl "$file" "$url" >&2 || return 1
			echo "$tag: ${src}/${name}  " >>"${cl_dir}/changelog.md"
		else
			local grab_cl="false"
			name=$(basename "$file")
			tag_name=$(cut -d'-' -f2- <<<"$name")
			tag_name=v${tag_name%.*}
		fi

		if [ "$tag" = "Patches" ]; then
			if [ "$grab_cl" = "true" ]; then echo -e "[Changelog](https://github.com/${src}/releases/tag/${tag_name})\n" >>"${cl_dir}/changelog.md"; fi
			if [ "$REMOVE_RV_INTEGRATIONS_CHECKS" = "true" ]; then
				local extensions_ext
				extensions_ext=$(unzip -l "${file}" "extensions/shared.*" 2>/dev/null | grep -o "shared\..*" || :)
				extensions_ext="${extensions_ext#*.}"
				if [ -z "$extensions_ext" ]; then
					# third-party bundles (e.g. hxreborn/morphe-patches) ship a single .mpp with
					# extensions/extension.mpe and no shared.* extension - nothing to rewrite
					pr "No extensions/shared.* in '$(basename "$file")', skipping integrations checks removal" >&2
				else
					# rewrite the shared extension in-place, but never fail the build over it -
					# on any error keep the original bundle (integrations checks remain, patch still works)
					if ! (
						set -e
						mkdir -p "${file}-zip"
						unzip -qo "${file}" -d "${file}-zip"
						java -cp "${BIN_DIR}/paccer.jar:${BIN_DIR}/dexlib2.jar" com.jhc.Main "${file}-zip/extensions/shared.${extensions_ext}" "${file}-zip/extensions/shared-patched.${extensions_ext}"
						mv -f "${file}-zip/extensions/shared-patched.${extensions_ext}" "${file}-zip/extensions/shared.${extensions_ext}"
						cd "${file}-zip"
						zip -0rq "${CWD}/${file}.pactmp" .
					) >&2; then
						wpr "Could not remove integrations checks from '$(basename "$file")'; keeping the original bundle"
						rm -f "${file}.pactmp"
					else
						mv -f "${file}.pactmp" "${file}"
					fi
					rm -r "${file}-zip" || :
				fi
			fi
		fi
		echo -n "$file "
	done
	echo
}

set_prebuilts() {
	APKSIGNER="${BIN_DIR}/apksigner.jar"
	APKEEP="${BIN_DIR}/apkeep" # APKPure-only downloader (https://github.com/EFForg/apkeep)
	local arch
	arch=$(uname -m)
	if [ "$arch" = aarch64 ]; then arch=arm64; elif [ "${arch:0:5}" = "armv7" ]; then arch=arm; fi
	HTMLQ="${BIN_DIR}/htmlq/htmlq-${arch}"
	AAPT2="${BIN_DIR}/aapt2/aapt2-${arch}"
	TOML="${BIN_DIR}/toml/tq-${arch}"
}

pick_patch_bundle() {
	# reads a GitHub release JSON on stdin; prints exactly one line:
	# "<tag_name>\t<asset_name>\t<digest>" where <digest> is the asset's native
	# digest field ("sha256:..."), or "-" when null/absent. Prints nothing and
	# returns 1 when no patch bundle asset is present in the release.
	local resp tag_name
	resp=$(cat)
	tag_name=$(jq -r '.tag_name // empty' <<<"$resp" 2>/dev/null) || return 1
	if [ -z "$tag_name" ]; then return 1; fi
	local candidates
	candidates=$(jq -c '[(.assets // [])[] | select(.name | test("\\.(asc|json|txt|md|yml|yaml|sig)$"; "i") | not)]' <<<"$resp") || return 1
	# prefer .mpp candidates when any exist
	local mpp
	mpp=$(jq -c '[.[] | select(.name | endswith(".mpp"))]' <<<"$candidates") || return 1
	if [ "$(jq 'length' <<<"$mpp")" -gt 0 ]; then
		candidates="$mpp"
	fi
	local count
	count=$(jq 'length' <<<"$candidates") || return 1
	if [ "$count" -eq 0 ]; then return 1; fi
	local name
	if [ "$count" -gt 1 ]; then
		# pick the candidate whose filename contains the highest dot-separated
		# numeric version (e.g. patches-2.2.0.mpp beats patches-2.1.0.mpp)
		name=$(jq -r '[ .[] | .name as $n | ((($n | capture("(?<v>[0-9]+(\\.[0-9]+)*)"))? // {v: "0"}).v | split(".") | map(tonumber)) as $ver | {name: $n, ver: $ver} ] | sort_by(.ver) | .[-1].name' <<<"$candidates") || return 1
	else
		name=$(jq -r '.[0].name' <<<"$candidates") || return 1
	fi
	if [ -z "$name" ]; then return 1; fi
	local digest
	digest=$(jq -r --arg n "$name" '(.assets // [])[] | select(.name == $n) | (.digest // "-")' <<<"$resp" | head -1) || digest="-"
	if [ -z "$digest" ] || [ "$digest" = "null" ]; then digest="-"; fi
	# prefix bare 64-char hex digests with sha256:; leave anything else as-is
	if [[ "$digest" =~ ^[0-9a-fA-F]{64}$ ]]; then digest="sha256:${digest}"; fi
	printf '%s\t%s\t%s\n' "$tag_name" "$name" "$digest"
}

config_update() {
	if [ ! -f build.md ]; then abort "build.md not available"; fi
	: >"$TEMP_DIR"/skipped
	: >"$TEMP_DIR"/rebuilt
	: >"$TEMP_DIR"/could-not-check
	: >"$TEMP_DIR"/seed-state.txt
	local upped=()
	local prcfg=false
	local considered=0 failed=0
	# per-app build state from the update branch.
	# new format:    <table>|<patches-src>|<tag>|<asset>|<digest>|<configured-version>
	# legacy format: <table>|<patches-src>|<asset>|<configured-version>
	local state_file="build-state.txt"
	[ -f "$state_file" ] || state_file=""
	declare -A latest_assets=()
	for table_name in $(toml_get_table_names); do
		if [ -z "$table_name" ]; then continue; fi
		t=$(toml_get_table "$table_name")
		enabled=$(toml_get "$t" enabled) || enabled=true
		if [ "$enabled" = "false" ]; then continue; fi
		PATCHES_SRC=$(toml_get "$t" patches-source) || PATCHES_SRC=$DEF_PATCHES_SRC
		PATCHES_VER=$(toml_get "$t" patches-version) || PATCHES_VER=$DEF_PATCHES_VER
		CFG_VER=$(toml_get "$t" version) || CFG_VER="auto"
		PATCHES_SRC="${PATCHES_SRC#"${PATCHES_SRC%%[![:space:]]*}"}"
		PATCHES_SRC="${PATCHES_SRC%"${PATCHES_SRC##*[![:space:]]}"}"
		PATCHES_VER="${PATCHES_VER#"${PATCHES_VER%%[![:space:]]*}"}"
		PATCHES_VER="${PATCHES_VER%"${PATCHES_VER##*[![:space:]]}"}"
		CFG_VER="${CFG_VER#"${CFG_VER%%[![:space:]]*}"}"
		CFG_VER="${CFG_VER%"${CFG_VER##*[![:space:]]}"}"
		considered=$((considered + 1))

		local src_key="${PATCHES_SRC}/${PATCHES_VER}" picked="" TAG_NAME="" NAME="" DIGEST=""
		if [ -n "${latest_assets[$src_key]+x}" ]; then
			picked="${latest_assets[$src_key]}"
		else
			local rv_rel="https://api.github.com/repos/${PATCHES_SRC}/releases" resp="" tag_name=""
			if [ "$PATCHES_VER" = "dev" ]; then
				if resp=$(gh_req "$rv_rel" -); then
					if ! resp=$(jq -e -r '.[0]' <<<"$resp"); then resp=""; fi
				else
					resp=""
				fi
			elif [ "$PATCHES_VER" = "latest" ]; then
				resp=$(gh_req "$rv_rel/latest" -) || resp=""
			else
				resp=$(gh_req "$rv_rel/tags/${PATCHES_VER}" -) || resp=""
			fi
			if [ -z "$resp" ]; then
				echo "${table_name}: GitHub API error" >>"$TEMP_DIR"/could-not-check
				failed=$((failed + 1))
				continue
			fi
			tag_name=$(jq -r '.tag_name // empty' <<<"$resp" 2>/dev/null) || tag_name=""
			if [ -z "$tag_name" ]; then
				echo "${table_name}: GitHub API error" >>"$TEMP_DIR"/could-not-check
				failed=$((failed + 1))
				continue
			fi
			if ! picked=$(pick_patch_bundle <<<"$resp") || [ -z "$picked" ]; then
				echo "${table_name}: no patch bundle asset found in release" >>"$TEMP_DIR"/could-not-check
				failed=$((failed + 1))
				continue
			fi
			latest_assets[$src_key]="$picked"
		fi
		IFS=$'\t' read -r TAG_NAME NAME DIGEST <<<"$picked"
		if [ -z "$NAME" ]; then
			echo "${table_name}: no patch bundle asset found in release" >>"$TEMP_DIR"/could-not-check
			failed=$((failed + 1))
			continue
		fi

		local state_line="" state_src="" state_tag="" state_name="" state_digest="" state_cfgver="" state_nf=0
		if [ -n "$state_file" ]; then
			state_line=$(awk -F'|' -v t="$table_name" '$1 == t { print; exit }' "$state_file" 2>/dev/null) || :
		fi
		if [ -n "$state_line" ]; then
			state_line="${state_line%$'\r'}"
			local fields=()
			IFS='|' read -r -a fields <<<"$state_line"
			local i f
			for i in "${!fields[@]}"; do
				f="${fields[$i]}"
				f="${f#"${f%%[![:space:]]*}"}"
				f="${f%"${f##*[![:space:]]}"}"
				fields[$i]="$f"
			done
			state_nf=${#fields[@]}
			if [ "$state_nf" -eq 4 ]; then
				# legacy format: table|src|asset|cfgver
				state_src="${fields[1]}"
				state_name="${fields[2]}"
				state_cfgver="${fields[3]}"
				state_tag="-"
				state_digest="-"
			elif [ "$state_nf" -ge 5 ]; then
				# new format, tolerate extra fields by taking from the right.
				# canonical suffix is ...|name|digest|cfgver (as written by
				# built-state.txt and the seed-state lines below):
				# table|src|tag|name|digest|cfgver (NF==6), or the same minus
				# the tag field (NF==5, tag unknown)
				state_cfgver="${fields[$((state_nf - 1))]}"
				state_digest="${fields[$((state_nf - 2))]}"
				state_name="${fields[$((state_nf - 3))]}"
				if [ "$state_nf" -ge 6 ]; then
					state_tag="${fields[$((state_nf - 4))]}"
				else
					state_tag="-"
				fi
				state_src="${fields[1]}"
			fi
		fi

		local changed=false reason="" app_line="" recorded_ver=""
		if [ -n "$state_line" ]; then
			if [ "$state_src" != "$PATCHES_SRC" ]; then
				changed=true reason="patch source changed"
			elif [ -n "$state_digest" ] && [ "$state_digest" != "-" ] && [ -n "$DIGEST" ] && [ "$DIGEST" != "-" ] && [ "$state_digest" != "$DIGEST" ]; then
				changed=true reason="patches updated"
			elif [ "$state_name" != "$NAME" ]; then
				changed=true reason="patches updated"
			elif [ "$CFG_VER" != "$state_cfgver" ]; then
				changed=true reason="configured version changed"
			fi
		elif [ -n "$state_file" ]; then
			# state file exists but has no line for this app (newly added): build it
			changed=true reason="no recorded build"
		else
			# migration path: no state file yet - fall back to build.md, then seed state below
			if ! grep -m1 "^Patches: ${PATCHES_SRC}/${NAME}" build.md >/dev/null; then
				changed=true reason="patches updated"
			fi
			app_line=$(grep -m1 -E "^${table_name}( \(|:)" build.md 2>/dev/null) || :
			if [ -n "$app_line" ]; then recorded_ver="${app_line##*: }"; fi
			recorded_ver="${recorded_ver%"${recorded_ver##*[![:space:]]}"}"
			recorded_ver="${recorded_ver#"${recorded_ver%%[![:space:]]*}"}"
			if [ -z "$recorded_ver" ]; then
				changed=true reason="no recorded build"
			elif [ "$CFG_VER" != "auto" ] && [ "$CFG_VER" != "$recorded_ver" ]; then
				changed=true reason="configured version changed"
			fi
			if [ "$changed" = false ]; then
				printf '%s|%s|%s|%s|%s|%s\n' "$table_name" "$PATCHES_SRC" "$TAG_NAME" "$NAME" "$DIGEST" "$CFG_VER" >>"$TEMP_DIR"/seed-state.txt
				echo "${table_name}: up to date, recorded" >>"$TEMP_DIR"/skipped
				continue
			fi
		fi

		if [ "$changed" = false ]; then
			echo "${table_name}: up to date (${NAME})" >>"$TEMP_DIR"/skipped
			if [ "$state_nf" -eq 4 ]; then
				# upgrade legacy state lines to the new format
				printf '%s|%s|%s|%s|%s|%s\n' "$table_name" "$PATCHES_SRC" "$TAG_NAME" "$NAME" "$DIGEST" "$CFG_VER" >>"$TEMP_DIR"/seed-state.txt
			fi
			continue
		fi

		if [ "$changed" = true ]; then
			prcfg=true
			upped+=("$table_name")
			echo "${table_name}: ${reason}" >>"$TEMP_DIR"/rebuilt
		fi
	done
	if [ "$considered" -gt 0 ] && [ "$failed" -eq "$considered" ]; then
		epr "all enabled apps failed their patch check"
		exit 1
	fi
	if [ "$prcfg" = true ]; then
		local query=""
		for table in "${upped[@]}"; do
			if [ -n "$query" ]; then query+=" or "; fi
			query+=".key == \"$table\""
		done
		jq "to_entries | map(select(${query} or (.value | type != \"object\"))) | from_entries" <<<"$__TOML__"
	fi
}

_req() {
	local ip="$1" op="$2"
	shift 2
	local dlp="$op"
	if [ "$op" != - ]; then
		if [ -f "$op" ]; then return; fi
		dlp="$(dirname "$op")/tmp.$(basename "$op")"
		if [ -f "$dlp" ]; then
			while [ -f "$dlp" ]; do sleep 1; done
			return
		fi
	fi
	if ! curl -L -c "$TEMP_DIR/cookie.txt" -b "$TEMP_DIR/cookie.txt" --connect-timeout 10 --retry 1 --fail -s -S "$@" "$ip" -o "$dlp"; then
		epr "Request failed: $ip"
		if [ "$dlp" != - ]; then rm -f "$dlp"; fi
		return 1
	fi
	if [ "$dlp" != - ]; then
		mv -f "$dlp" "$op"
	fi
}
req() { _req "$1" "$2" -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:108.0) Gecko/20100101 Firefox/108.0"; }
gh_req() { _req "$1" "$2" -H "$GH_HEADER"; }
gh_dl() {
	if [ ! -f "$1" ]; then
		pr "Getting '$1' from '$2'"
		_req "$2" "$1" -H "$GH_HEADER" -H "Accept: application/octet-stream"
	fi
}

log() { echo -e "$1  " >>"build.md"; }
get_highest_ver() {
	local vers m
	vers=$(tee)
	m=$(head -1 <<<"$vers")
	if ! semver_validate "$m"; then echo "$m"; else sort -s -t- -k1,1Vr <<<"$vers" | head -1; fi
}
semver_validate() {
	local a="${1%-*}"
	local a="${a#v}"
	local ac="${a//[.0-9]/}"
	[ ${#ac} = 0 ]
}
get_patch_last_supported_ver() {
	local list_patches=$1 pkg_name=$2 inc_sel=$3 is_experimental=$4
	# _exc_sel=$4 _exclusive=$5
	local op
	if [ "$inc_sel" ]; then
		if ! op=$(awk '{$1=$1}1' <<<"$list_patches"); then
			epr "list-patches: '$op'"
			return 1
		fi
		local ver vers="" NL=$'\n'
		while IFS= read -r line; do
			line="${line:1:${#line}-2}"
			ver=$(sed -n "/^Name: $line\$/,/^\$/p" <<<"$op" | sed -n "/^Compatible versions:\$/,/^\$/p" | tail -n +2)
			vers=${ver}${NL}
		done <<<"$(list_args "$inc_sel")"
		vers=$(awk '{$1=$1}1' <<<"$vers")
		if [ "$vers" ]; then
			get_highest_ver <<<"$vers"
			return
		fi
	fi
	op=$(patches_list_versions "$cli_jar" "$patches_jar" "$pkg_name" "$is_experimental") || return 1
	op=$(sed -n '/Most common compatible versions:/,$p' <<<"$op" | awk 'NR > 1 {print $1}')
	if [ -z "$op" ]; then
		abort "No patches found for '$pkg_name' in patches '$patches_jar'"
	elif [ "$op" = "Any" ]; then
		return
	fi
	get_highest_ver <<<"$op" || return 1
}

patches_list_versions() {
	local cli_jar=$1 patches_jar=$2 pkg_name=$3 is_experimental=$4
	local cmd_base="java -jar '$cli_jar' list-versions"

	# TODO: remove this later
	local cli_name
	cli_name=$(basename "$cli_jar")
	if [ "${cli_name::8}" = "revanced" ]; then
		cmd_base+=" -b"
	elif [ "$is_experimental" = "true" ]; then
		cmd_base+=" -x"
	fi

	local cmd="${cmd_base} --patches='$patches_jar' -f '$pkg_name'"
	if op=$(eval "$cmd" 2>&1); then
		echo "$op"
		return
	fi

	cmd="${cmd_base} '$patches_jar' -f '$pkg_name'"
	if op=$(eval "$cmd" 2>&1); then
		echo "$op"
		return
	fi

	epr "Could not list versions ($pkg_name) $cli_jar: '$op'"
	return 1
}
patches_list() {
	local cli_jar=$1 patches_jar=$2 pkg_name=$3 is_experimental=$4
	local op
	if ! op=$(java -jar "$cli_jar" list-patches -p "$patches_jar" --filter-package-name "$pkg_name" --versions --packages -b 2>&1); then
		local cmd="java -jar '$cli_jar' list-patches --patches '$patches_jar' -f '$pkg_name' --with-versions --with-packages"
		if [ "$is_experimental" = "true" ]; then cmd+=" -x"; fi
		if ! op=$(eval "$cmd" 2>&1); then
			epr "Could not get patches list ($pkg_name) $cli_jar: '$op'"
			return 1
		fi

	fi
	echo "$op"
}

isoneof() {
	local i=$1 v
	shift
	for v; do [ "$v" = "$i" ] && return 0; done
	return 1
}

merge_splits() {
	local bundle=$1 output=$2
	pr "Merging splits"
	if [ ! -f "$TEMP_DIR/apkeditor.jar" ]; then
		local resp dlurl
		resp=$(gh_req "https://api.github.com/repos/REAndroid/APKEditor/releases/latest" -) || return 1
		dlurl=$(jq -e -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' <<<"$resp") || return 1
		gh_dl "$TEMP_DIR/apkeditor.jar" "$dlurl" >/dev/null || return 1
	fi
	if ! OP=$(java -jar "$TEMP_DIR/apkeditor.jar" merge -i "$bundle" -o "${output}-unsigned" -clean-meta -f 2>&1); then
		epr "APKEditor error: $OP"
		return 1
	fi
	# sign the merged stock apk
	if ! OP=$(java -jar "$APKSIGNER" sign --ks ks-p12.keystore --ks-pass pass:123456789 --key-pass pass:123456789 --ks-key-alias jhc \
		--out "${output}" "${output}-unsigned"); then
		epr "apksigner error: $OP"
		return 1
	fi
	rm "${output}.idsig" "${output}-unsigned" 2>/dev/null || :
	return 0
}

# -------------------- apkmirror --------------------
apkmirror_search() {
	local resp="$1" dpi="$2" arch="$3" apk_bundle="$4"
	local dlurl="" node app_table emptyCheck

	local apparch=('universal' 'noarch' 'arm64-v8a + armeabi-v7a')
	if [ "$arch" != "all" ]; then
		apparch+=("$arch")
	fi

	local appdpi=("nodpi" "anydpi")
	if [ "$dpi" ]; then
		appdpi+=($dpi)
	fi

	for ((n = 1; n < 40; n++)); do
		node=$($HTMLQ "div.table-row.headerFont:nth-last-child($n)" -r "span:nth-child(n+3)" <<<"$resp")
		if [ -z "$node" ]; then break; fi
		emptyCheck=$($HTMLQ -t -w "div.table-cell:nth-child(1) > a:nth-child(1)" <<<"$node" | xargs)
		if [ -z "$emptyCheck" ]; then break; fi
		app_table=$($HTMLQ --text --ignore-whitespace <<<"$node")
		if [ "$(sed -n 3p <<<"$app_table")" != "$apk_bundle" ]; then continue; fi
		dlurl=$($HTMLQ --base https://www.apkmirror.com --attribute href "div:nth-child(1) > a:nth-child(1)" <<<"$node")
		if isoneof "$(sed -n 6p <<<"$app_table")" "${appdpi[@]}" &&
			isoneof "$(sed -n 4p <<<"$app_table")" "${apparch[@]}"; then
			echo "$dlurl"
			return 0
		fi
	done
	if [ "$n" -eq 2 ] && [ "$dlurl" ]; then
		# only one apk exists, return it
		echo "$dlurl"
		return 0
	fi
	return 1
}
dl_apkmirror() {
	local url=$1 version=${2// /-} output=$3 arch=$4 dpi=$5 is_bundle=false

	if [ -f "${output}.apkm" ]; then
		merge_splits "${output}.apkm" "${output}"
		return 0
	fi

	if [ "$arch" = "arm-v7a" ]; then arch="armeabi-v7a"; fi
	local resp node app_table apkmname dlurl=""
	apkmname=$($HTMLQ "h1.marginZero" --text <<<"$__APKMIRROR_RESP__")
	apkmname="${apkmname,,}" apkmname="${apkmname// /-}" apkmname="${apkmname//[^a-z0-9-]/}"
	url="${url}/${apkmname}-${version//./-}-release/"
	resp=$(req "$url" -) || return 1
	node=$($HTMLQ "div.table-row.headerFont:nth-last-child(1)" -r "span:nth-child(n+3)" <<<"$resp")
	if [ "$node" ]; then
		for type in APK BUNDLE; do
			if dlurl=$(apkmirror_search "$resp" "$dpi" "$arch" "$type"); then
				if [ "$type" = "BUNDLE" ]; then
					is_bundle=true
				else is_bundle=false; fi
				break 2
			fi
		done
		if [ -z "$dlurl" ]; then return 1; fi
		resp=$(req "$dlurl" -)
	fi
	url=$(echo "$resp" | $HTMLQ --base https://www.apkmirror.com --attribute href "a.btn") || return 1
	url=$(req "$url" - | $HTMLQ --base https://www.apkmirror.com --attribute href "span > a[rel = nofollow]") || return 1

	if [ "$is_bundle" = true ]; then
		req "$url" "${output}.apkm" || return 1
		merge_splits "${output}.apkm" "${output}"
	else
		req "$url" "${output}" || return 1
	fi
}
get_apkmirror_vers() {
	local vers apkm_resp
	apkm_resp=$(req "https://www.apkmirror.com/uploads/?appcategory=${__APKMIRROR_CAT__}" -)
	vers=$(sed -n 's;.*Version:</span><span class="infoSlide-value">\(.*\) </span>.*;\1;p' <<<"$apkm_resp" | awk '{$1=$1}1')

	vers=$(grep -iv "\(beta\|alpha\)" <<<"$vers")
	local v r_vers=()
	local IFS=$'\n'
	for v in $vers; do
		grep -iq "${v} \(beta\|alpha\)" <<<"$apkm_resp" || r_vers+=("$v")
	done
	echo "${r_vers[*]}"
}
get_apkmirror_pkg_name() { sed -n 's;.*id=\(.*\)" class="accent_color.*;\1;p' <<<"$__APKMIRROR_RESP__"; }
get_apkmirror_resp() {
	__APKMIRROR_RESP__=$(req "${1}" -) || return 1
	__APKMIRROR_CAT__="${1##*/}"
}

# -------------------- uptodown --------------------
get_uptodown_resp() {
	__UPTODOWN_RESP__=$(req "${1}/versions" -) || return 1
	__UPTODOWN_RESP_PKG__=$(req "${1}/download" -) || return 1
}
get_uptodown_vers() { $HTMLQ --text ".version" <<<"$__UPTODOWN_RESP__"; }
dl_uptodown() {
	local uptodown_dlurl=$1 version=$2 output=$3 arch=$4 _dpi=$5
	if [ "$arch" = "arm-v7a" ]; then arch="armeabi-v7a"; fi

	local apparch=('arm64-v8a, armeabi-v7a, x86_64' 'arm64-v8a, armeabi-v7a, x86, x86_64' 'arm64-v8a, armeabi-v7a')
	if [ "$arch" != "all" ]; then
		apparch+=("$arch")
	fi

	local op resp data_code
	data_code=$($HTMLQ "#detail-app-name" --attribute data-code <<<"$__UPTODOWN_RESP__")
	local versionURL=""
	local is_bundle=false
	for i in {1..20}; do
		resp=$(req "${uptodown_dlurl}/apps/${data_code}/versions/${i}" -)
		if ! op=$(jq -e -r ".data | map(select(.version == \"${version}\")) | .[0]" <<<"$resp"); then
			continue
		fi
		if [ "$(jq -e -r ".kindFile" <<<"$op")" = "xapk" ]; then is_bundle=true; fi
		if versionURL=$(jq -e -r '.versionURL' <<<"$op"); then break; else return 1; fi
	done
	if [ -z "$versionURL" ]; then return 1; fi
	versionURL=$(jq -e -r '.url + "/" + .extraURL + "/" + (.versionID | tostring)' <<<"$versionURL")
	resp=$(req "$versionURL" -) || return 1

	local data_version files node_arch="" data_file_id node_class
	data_version=$($HTMLQ '.button.variants' --attribute data-version <<<"$resp") || return 1
	if [ "$data_version" ]; then
		files=$(req "${uptodown_dlurl%/*}/app/${data_code}/version/${data_version}/files" - | jq -e -r .content) || return 1
		for ((n = 1; n < 12; n += 1)); do
			node_class=$($HTMLQ -w -t ".content > :nth-child($n)" --attribute class <<<"$files") || return 1
			if [ "$node_class" != "variant" ]; then
				node_arch=$($HTMLQ -w -t ".content > :nth-child($n)" <<<"$files" | xargs) || return 1
				continue
			fi
			if [ -z "$node_arch" ]; then return 1; fi
			if ! isoneof "$node_arch" "${apparch[@]}"; then continue; fi

			file_type=$($HTMLQ -w -t ".content > :nth-child($n) > .v-file > span" <<<"$files") || return 1
			if [ "$file_type" = "xapk" ]; then is_bundle=true; else is_bundle=false; fi
			data_file_id=$($HTMLQ ".content > :nth-child($n) > .v-report" --attribute data-file-id <<<"$files") || return 1
			resp=$(req "${uptodown_dlurl}/download/${data_file_id}-x" -)
			break
		done
		if [ $n -eq 12 ]; then return 1; fi
	fi
	local data_url
	data_url=$($HTMLQ "#detail-download-button" --attribute data-url <<<"$resp") || return 1
	if [ $is_bundle = true ]; then
		req "https://dw.uptodown.com/dwn/${data_url}" "$output.apkm" || return 1
		merge_splits "${output}.apkm" "${output}"
	else
		req "https://dw.uptodown.com/dwn/${data_url}" "$output"
	fi
}
get_uptodown_pkg_name() { $HTMLQ --text "tr.full:nth-child(1) > td:nth-child(3)" <<<"$__UPTODOWN_RESP_PKG__"; }

# -------------------- archive --------------------
dl_archive() {
	local url=$1 version=$2 output=$3 arch=$4
	local path version=${version// /}

	if [ -f "${output}.apkm" ]; then
		merge_splits "${output}.apkm" "$output"
		return 0
	fi

	if ! path=$(grep -m1 "${version_f#v}-${arch// /}" <<<"$__ARCHIVE_RESP__"); then
		path=$(grep -m1 "${version_f#v}-all" <<<"$__ARCHIVE_RESP__") || return 1
	fi

	if [ "${path##*.}" = "apkm" ]; then
		req "${url}/${path}" "${output}.apkm" || return 1
		merge_splits "${output}.apkm" "$output"
	else
		req "${url}/${path}" "${output}" || return 1
	fi
}
get_archive_resp() {
	__ARCHIVE_PKG_NAME__=$(awk -F/ '{print $NF}' <<<"$1")
	local r
	r=$(req "$1" -)
	if [ -z "$r" ]; then return 1; else __ARCHIVE_RESP__=$(sed -n 's;^<a href="\(.*\)"[^"]*;\1;p' <<<"$r"); fi
}
get_archive_vers() { sed 's/^[^-]*-//;s/-\(all\|arm64-v8a\|arm-v7a\)\.\(apk\|apkm\)//g' <<<"$__ARCHIVE_RESP__"; }
get_archive_pkg_name() { echo "$__ARCHIVE_PKG_NAME__"; }

# -------------------- direct --------------------
dl_direct() {
	local url=$1 version=${2// /-} output=$3 arch=$4 _dpi=$5
	if ! grep -q "${version_f#v}-${arch// /}" <<<"$url"; then
		epr "Given direct-dlurl for $output is not compatible. Set proper 'arch' and 'version' options."
		return 1
	fi
	if [ "${url##*.}" = "apkm" ]; then
		req "$url" "${output}.apkm" || return 1
		merge_splits "${output}.apkm" "$output"
	else
		req "$url" "${output}" || return 1
	fi
}
get_direct_vers() { cut -d- -f2 <<<"$__DIRECT_APKNAME__"; }
get_direct_pkg_name() { cut -d- -f1 <<<"$__DIRECT_APKNAME__"; }
get_direct_resp() { __DIRECT_APKNAME__=$(awk -F/ '{print $NF}' <<<"$1"); }
# -------------------- apkpure --------------------
# APKPure downloads go through apkeep (https://github.com/EFForg/apkeep), which
# is only ever invoked with the apk-pure download source. The 'apkpure-dlurl'
# config option holds the app's package id on APKPure (e.g. com.streetwriters.notesnook).
# returns 0 if the bundle has arm64-v8a native libs (or none at all); 1 otherwise.
# this project only supports arm64-v8a.
arm64_ok() {
	local dump
	dump=$(unzip -l "$1" 2>/dev/null)
	if grep -qE 'lib/(x86|x86_64|armeabi-v7a|armeabi)/' <<<"$dump" && ! grep -qE 'lib/arm64-v8a/|config\.arm64_v8a\.apk' <<<"$dump"; then
		return 1
	fi
	return 0
}
get_apkpure_resp() {
	local app_id="$1"
	if [ ! -x "$APKEEP" ]; then
		epr "apkeep binary not found at '$APKEEP'"
		return 1
	fi
	app_id=$(sed 's/[[:space:]]//g' <<<"$app_id")
	__APKPURE_APP_ID__="$app_id"
	__APKPURE_RESP__=$("$APKEEP" -l -a "$__APKPURE_APP_ID__" -d apk-pure -o 'output_format=json' 2>&1 || :)
	if ! grep -q '"available_versions"' <<<"$__APKPURE_RESP__"; then
		epr "Could not get '$__APKPURE_APP_ID__' from apkpure"
		return 1
	fi
	return 0
}
get_apkpure_vers() {
	jq -r --arg id "$__APKPURE_APP_ID__" '.apps[$id].available_versions[].version' <<<"$__APKPURE_RESP__" | tr '\n' ' '
	echo
}
get_apkpure_pkg_name() { echo "$__APKPURE_APP_ID__"; }
dl_apkpure() {
	local app_id=$1 version=${2// /} output=$3 arch=$4 _dpi=$5
	version="${version#v}"
	if [ -f "${output}.xapk" ]; then
		if [[ $arch == *arm64* ]] && ! arm64_ok "${output}.xapk"; then
			epr "Cached bundle '${output}.xapk' has no arm64-v8a native libraries; deleting and re-downloading"
			rm -f "${output}.xapk"
		else
			merge_splits "${output}.xapk" "$output"
			return $?
		fi
	fi
	if [ ! -x "$APKEEP" ]; then
		epr "apkeep binary not found at '$APKEEP'"
		return 1
	fi
	# 'arch' is passed through to apkeep when set to a specific abi (default on apkpure is "all")
	# note: apkeep names the output "<id>[@<version>[@<arch>]].<apk|xapk>"
	local opts="acknowledge_dangers=true" arch_suffix=""
	if [ "$arch" != "all" ]; then
		local apkeep_arch="$arch"
		if [ "$arch" = "arm-v7a" ]; then apkeep_arch="armeabi-v7a"; fi
		if [ "$arch" != "both" ]; then opts+=",arch=${apkeep_arch}"; arch_suffix="@${apkeep_arch}"; fi
	fi
	if ! "$APKEEP" -a "${app_id}@${version}" -d apk-pure -o "$opts" "$TEMP_DIR"; then
		epr "apkeep failed to download '${app_id}@${version}' from apkpure"
		return 1
	fi
	local dlfile="" cand
	for cand in \
		"${app_id}@${version}${arch_suffix}.apk" "${app_id}@${version}${arch_suffix}.xapk" \
		"${app_id}@${version}.apk" "${app_id}@${version}.xapk" \
		"${app_id}${arch_suffix}.apk" "${app_id}${arch_suffix}.xapk" \
		"${app_id}.apk" "${app_id}.xapk"; do
		if [ -f "$TEMP_DIR/$cand" ]; then dlfile="$TEMP_DIR/$cand"; break; fi
	done
	if [ -z "$dlfile" ]; then
		epr "apkeep did not produce an apk/xapk for '${app_id}@${version}'"
		return 1
	fi
	if [[ $arch == *arm64* ]] && ! arm64_ok "$dlfile"; then
		epr "Downloaded bundle for '${app_id}@${version}' contains only non-arm64-v8a native libraries; this project only supports arm64-v8a"
		return 1
	fi
	if [ "${dlfile##*.}" = "xapk" ]; then
		mv -f "$dlfile" "${output}.xapk"
		merge_splits "${output}.xapk" "$output"
	else
		mv -f "$dlfile" "$output"
	fi
}
# -------------------- official --------------------
# Official app downloads: config option 'official-dlurl' points directly at the
# vendor's download endpoint (e.g. Notesnook's API, which 302-redirects to the
# official GitHub release asset). 'pkg-name' must be set in the config as well.
# Note: when the endpoint serves a version newer than the patches support, the
# patch step fails loudly - that's expected; wait for a patch update or pin 'version'.
get_official_resp() {
	__OFFICIAL_URL__=$(sed 's/[[:space:]]//g' <<<"$1")
	local code
	# 1-byte ranged GET: works even on signed asset URLs that dislike HEAD
	code=$(curl -s -o /dev/null -w "%{http_code}" -L --connect-timeout 10 --retry 1 -r 0-0 "$__OFFICIAL_URL__" || :)
	if [[ ! "$code" =~ ^(200|206)$ ]]; then
		epr "Official APK endpoint returned HTTP ${code:-000}: $__OFFICIAL_URL__"
		return 1
	fi
	return 0
}
get_official_vers() {
	epr "official-dlurl serves 'latest' and has no version list; set 'version' in the config or use patches-resolved 'auto'"
	return 1
}
get_official_pkg_name() {
	epr "official source requires 'pkg-name' in the config (e.g. pkg-name = \"com.example.app\")"
	return 1
}
dl_official() {
	local url=$1 version=${2// /} output=$3 arch=$4 _dpi=$5
	version="${version#v}"
	if ! req "$url" "$output"; then
		epr "Could not download the official APK from '$url'"
		return 1
	fi
	if [[ $arch == *arm64* ]] && ! arm64_ok "$output"; then
		epr "Official APK from '$url' contains no arm64-v8a native libraries; this project only supports arm64-v8a"
		rm -f "$output"
		return 1
	fi
}
# --------------------------------------------------

patch_apk() {
	local stock_input=$1 patched_apk=$2 patcher_args=$3 cli_jar=$4 patches_jar=$5
	local tmp_files
	tmp_files="$(pwd)/$(mktemp -d -p "$TEMP_DIR")"

	local cmd="java -jar '$cli_jar' patch '$stock_input' -o '$patched_apk' -p '$patches_jar' --keystore=ks.keystore \
--keystore-entry-password=123456789 --keystore-password=123456789 --signer=jhc --keystore-entry-alias=jhc -t '$tmp_files' $patcher_args"

	# TODO: remove this later
	local cli_name
	cli_name=$(basename "$cli_jar")
	if [ "${cli_name::8}" = "revanced" ]; then
		cmd+=" -b"
		if [ "$OS" = "Android" ]; then cmd+=" --custom-aapt2-binary='${AAPT2}'"; fi
	fi

	pr "$cmd"
	if eval "$cmd"; then [ -f "$patched_apk" ]; else
		rm "$patched_apk" 2>/dev/null || :
		return 1
	fi
}

check_sig() {
	local file=$1 pkg_name=$2
	local sig
	if grep -q "$pkg_name" sig.txt; then
		sig=$(java -jar "$APKSIGNER" verify --print-certs "$file" | grep ^Signer | grep SHA-256 | tail -1 | awk '{print $NF}')
		echo "$pkg_name signature: ${sig}"
		grep -qFx "$sig $pkg_name" sig.txt
	fi
}

build_rv() {
	eval "declare -A args=${1#*=}"
	local version="" pkg_name=""
	local mode_arg=${args[build_mode]} version_mode=${args[version]}
	local app_name=${args[app_name]}
	local app_name_l=${app_name,,}
	app_name_l=${app_name_l// /-}
	local table=${args[table]}
	local dl_from=${args[dl_from]}
	local arch=${args[arch]}
	local arch_f="${arch// /}"

	local p_patcher_args=()
	if [ "${args[excluded_patches]}" ]; then p_patcher_args+=("$(join_args "${args[excluded_patches]}" -d)"); fi
	if [ "${args[included_patches]}" ]; then p_patcher_args+=("$(join_args "${args[included_patches]}" -e)"); fi
	[ "${args[exclusive_patches]}" = true ] && p_patcher_args+=("--exclusive")

	local tried_dl=()
	if [ "${args[pkg_name]}" ]; then
		pkg_name="${args[pkg_name]}"
	else
		for dl_p in "${DL_SRCS[@]}"; do
			if [ -z "${args[${dl_p}_dlurl]}" ]; then continue; fi
			if ! get_"${dl_p}"_resp "${args[${dl_p}_dlurl]}" || ! pkg_name=$(get_"${dl_p}"_pkg_name); then
				args[${dl_p}_dlurl]=""
				epr "ERROR: Could not find ${table} in ${dl_p}"
				continue
			fi
			tried_dl+=("$dl_p")
			dl_from=$dl_p
			break
		done
	fi

	if [ -z "$pkg_name" ]; then
		epr "empty pkg name, not building ${table}."
		return 0
	fi
	pr "Package name of '${table}' is '$pkg_name'"
	local list_patches

	local is_experimental="false"
	if [ "$version_mode" = "experimental" ]; then is_experimental="true"; fi
	list_patches=$(patches_list "$cli_jar" "$patches_jar" "$pkg_name" "$is_experimental") || return 1
	local get_latest_ver=false
	if isoneof "$version_mode" "auto" "experimental"; then
		if ! version=$(get_patch_last_supported_ver "$list_patches" "$pkg_name" "${args[included_patches]}" "$is_experimental"); then
			epr "get_patch_last_supported_ver failed '$list_patches'"
			return
		elif [ -z "$version" ]; then get_latest_ver="true"; fi
	elif [ "$version_mode" = "latest" ]; then
		get_latest_ver="true"
		p_patcher_args+=("-f")
	else
		version=$version_mode
		p_patcher_args+=("-f")
	fi
	if [ $get_latest_ver = "true" ]; then
		if ! isoneof "$dl_from" "${tried_dl[@]}"; then
			if ! get_"${dl_from}"_resp "${args[${dl_from}_dlurl]}"; then
				abort "ERROR: Could not get '${table}' from '${dl_from}'"
			fi
		fi
		pkgvers=$(get_"${dl_from}"_vers)
		version=$(get_highest_ver <<<"$pkgvers") || version=$(head -1 <<<"$pkgvers")
	fi
	if [ -z "$version" ]; then
		epr "empty version, not building ${table}."
		return 0
	fi

	if [ "$mode_arg" = module ]; then
		build_mode_arr=(module)
	elif [ "$mode_arg" = apk ]; then
		build_mode_arr=(apk)
	elif [ "$mode_arg" = both ]; then
		build_mode_arr=(apk module)
	fi

	pr "Choosing version '${version}' for ${table}"
	local version_f=${version// /}
	version_f=${version_f#v}
	local stock_apk="${TEMP_DIR}/${pkg_name}-${version_f}-${arch_f}.apk"
	if [ ! -f "$stock_apk" ]; then
		for dl_p in "${DL_SRCS[@]}"; do
			if [ -z "${args[${dl_p}_dlurl]}" ]; then continue; fi
			pr "Downloading '${table}' from '${dl_p}'"
			if ! isoneof "$dl_p" "${tried_dl[@]}"; then
				if ! get_"${dl_p}"_resp "${args[${dl_p}_dlurl]}"; then
					epr "ERROR: Could not get '${table}' from '${dl_p}'"
					continue
				fi
			fi
			if ! dl_"${dl_p}" "${args[${dl_p}_dlurl]}" "$version" "$stock_apk" "$arch" "${args[dpi]}" "$get_latest_ver"; then
				epr "ERROR: Could not download '${table}' from '${dl_p}' with version '${version}', arch '${arch}', dpi '${args[dpi]}'"
				continue
			fi
			break
		done
		if [ ! -f "$stock_apk" ]; then
			epr "Stock apk not found ($stock_apk)"
			return 0
		fi
	fi

	local sig_op split_bundle=""
	if [ -f "${stock_apk}.apkm" ]; then split_bundle="${stock_apk}.apkm"; fi
	if [ -f "${stock_apk}.xapk" ]; then split_bundle="${stock_apk}.xapk"; fi
	if [ -n "$split_bundle" ]; then
		rm -rf "${stock_apk}-zip" || :
		mkdir -p "${stock_apk}-zip"
		unzip -j "$split_bundle" -d "${stock_apk}-zip" >/dev/null 2>&1 || :
		local a
		a=$(find "${stock_apk}-zip" -type f -name "base.apk" -print -quit)
		# no base.apk? the biggest apk in a split bundle is the base apk (splits are small config.*)
		if [ -z "$a" ]; then a=$(find "${stock_apk}-zip" -type f -name "*.apk" -printf "%s\t%p\n" | sort -rn | cut -f2- | head -1); fi
		if [ -z "$a" ]; then
			epr "Could not find the base apk inside '$split_bundle'"
			return 0
		fi
		if ! sig_op=$(check_sig "$a" "$pkg_name" 2>&1); then
			epr "Not building $table, apk signature mismatch '$a': $sig_op"
			return 0
		fi
		rm -rf "${stock_apk}-zip" || :
	else
		if ! sig_op=$(check_sig "$stock_apk" "$pkg_name" 2>&1); then
			epr "Not building $table, apk signature mismatch '$stock_apk': $sig_op"
			return 0
		fi
	fi
	log "${table}: ${version}"
	if [ "${args[patcher_args]}" ]; then p_patcher_args+=("${args[patcher_args]}"); fi

	local branding_patch
	branding_patch=$(grep "^Name: " <<<"$list_patches" | grep -i "custom branding" || :) branding_patch=${branding_patch#*: }
	if [[ ${p_patcher_args[*]} =~ $branding_patch ]]; then
		branding_patch=""
	fi

	local microg_patch
	microg_patch=$(grep "^Name: " <<<"$list_patches" | grep -i "gmscore\|microg" || :) microg_patch=${microg_patch#*: }
	if [ -n "$microg_patch" ] && [[ ${p_patcher_args[*]} =~ $microg_patch ]]; then
		wpr "Cannot include/exclude microg patch as that's done by rvmm builder automatically."
		p_patcher_args=("${p_patcher_args[@]//-[ei] ${microg_patch}/}")
	fi

	local patcher_args patched_apk build_mode
	local rv_brand_f=${args[rv_brand],,}
	rv_brand_f=${rv_brand_f// /-}
	for build_mode in "${build_mode_arr[@]}"; do
		patcher_args=("${p_patcher_args[@]}")
		pr "Building '${table}' in '$build_mode' mode"
		if [ -n "$microg_patch" ]; then
			patched_apk="${TEMP_DIR}/${app_name_l}-${rv_brand_f}-${version_f}-${arch_f}-${build_mode}.apk"
		else
			patched_apk="${TEMP_DIR}/${app_name_l}-${rv_brand_f}-${version_f}-${arch_f}.apk"
		fi

		if [ "$build_mode" = "apk" ]; then
			if [ -n "$microg_patch" ]; then
				patcher_args+=("-e \"${microg_patch}\"")
			fi
		elif [ "$build_mode" = "module" ]; then
			if [ -n "$microg_patch" ]; then
				patcher_args+=("-d \"${microg_patch}\"")
			fi
			if [ -n "$branding_patch" ]; then
				patcher_args+=("-d \"${branding_patch}\"")
			fi
		else
			abort unreachable
		fi

		if [ "${args[enable_update_checks]}" = "true" ] && [ "$build_mode" = "apk" ] && [ -n "${GITHUB_REPOSITORY-}" ]; then
			local p="$TEMP_DIR/jhc-update-check.mpp"
			if [ ! -f $p ]; then
				local resp dlurl
				resp=$(gh_req "https://api.github.com/repos/j-hc/morphe-jhc-update-check-patch/releases/latest" -) || return 1
				dlurl=$(jq -e -r '.assets[0] | .browser_download_url' <<<"$resp") || return 1
				gh_dl $p "$dlurl" >/dev/null || return 1
			fi
			patcher_args+=("-p '$p'")

			local v
			v=$(git tag --sort=committerdate | tail -1) || :
			if [[ $v =~ ^[0-9]+$ ]]; then
				v=$((v + 1))
				patcher_args+=("-e 'j-hc Update Check'")
				patcher_args+=("-e 'j-hc Update Check Res' -OcurrentTag='\"$v\"' -OupdateRepo='\"${GITHUB_REPOSITORY}\"'")
			else
				epr "'$v' is not a proper version tag"
			fi
		fi

		if grep -Fq -- '--striplibs' <<<"$(java 2>&1 -jar "$cli_jar" patch)"; then
			# bug in --striplibs ?
			if [ "$build_mode" = "module" ]; then
				patcher_args+=("--striplibs mips")
			else
				if [ "$arch" = "arm64-v8a" ]; then
					patcher_args+=("--striplibs arm64-v8a")
				elif [ "$arch" = "arm-v7a" ]; then
					patcher_args+=("--striplibs armeabi-v7a")
				elif [ "$arch" = "x86" ]; then
					patcher_args+=("--striplibs x86")
				elif [ "$arch" = "x86_64" ]; then
					patcher_args+=("--striplibs x86_64")
				else
					patcher_args+=("--striplibs arm64-v8a,armeabi-v7a")
				fi
			fi
		fi

		local apk_output="${BUILD_DIR}/${app_name_l}-${rv_brand_f}-v${version_f}-${arch_f}.apk"
		if [ "${NORB:-}" != true ] || { [ ! -f "$patched_apk" ] && [ ! -f "$apk_output" ]; }; then
			if ! patch_apk "$stock_apk" "$patched_apk" "${patcher_args[*]}" "${args[cli]}" "${args[ptjar]}"; then
				epr "Building '${table}' failed!"
				return 0
			fi
		fi
		if [ "$build_mode" = apk ]; then
			if [ "${NORB:-}" != true ] || { [ ! -f "$patched_apk" ] && [ ! -f "$apk_output" ]; }; then
				mv -f "$patched_apk" "$apk_output"
			else
				cp -f "$patched_apk" "$apk_output"
			fi
			pr "Built ${table} (non-root): '${apk_output}'"
			continue
		fi
		local base_template
		base_template=$(mktemp -d -p "$TEMP_DIR")
		cp -a $MODULE_TEMPLATE_DIR/. "$base_template"
		local upj="${table,,}-update.json"

		module_config "$base_template" "$pkg_name" "$version" "$arch"

		local patches_ver="${patches_jar##*-}"
		module_prop \
			"${args[module_prop_name]}" \
			"${app_name} ${args[rv_brand]}" \
			"${version} (patches ${patches_ver})" \
			"${app_name} ${args[rv_brand]} module" \
			"https://raw.githubusercontent.com/${GITHUB_REPOSITORY-}/update/${upj}" \
			"$base_template"

		local module_output="${app_name_l}-${rv_brand_f}-module-v${version_f}-${arch_f}.zip"
		pr "Packing module ${table}"
		cp -f "$patched_apk" "${base_template}/base.apk"

		if [ "${args[include_stock]}" != "disable" ]; then
			mkdir -p "${base_template}/stock/"
			if [ "${args[include_stock]}" = "merged" ]; then
				cp -f "$stock_apk" "${base_template}/stock/base.apk"
			elif [ "${args[include_stock]}" = "split" ]; then
				if [ ! -f "${stock_apk}.apkm" ]; then
					epr "Cannot include as 'split' because stock apk of $table_name is not a bundle"
					return 0
				fi
				if [ "$arch" = "arm64-v8a" ]; then
					unzip -j "${stock_apk}.apkm" '*.apk' -x '*x86_64.apk' -x '*x86.apk' -x '*armeabi_v7a.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				elif [ "$arch" = "arm-v7a" ]; then
					unzip -j "${stock_apk}.apkm" '*.apk' -x '*x86_64.apk' -x '*x86.apk' -x '*arm64_v8a.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				elif [ "$arch" = "x86" ]; then
					unzip -j "${stock_apk}.apkm" '*.apk' -x '*x86_64.apk' -x '*arm64_v8a.apk' -x '*armeabi_v7a.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				elif [ "$arch" = "x86_64" ]; then
					unzip -j "${stock_apk}.apkm" '*.apk' -x '*x86.apk' -x '*arm64_v8a.apk' -x '*armeabi_v7a.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				else
					unzip -j "${stock_apk}.apkm" '*.apk' -x '*x86_64.apk' -x '*x86.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				fi
			fi
		fi

		pushd >/dev/null "$base_template" || abort "Module template dir not found"
		zip -"$COMPRESSION_LEVEL" -FSqr "${CWD}/${BUILD_DIR}/${module_output}" .
		popd >/dev/null || :
		pr "Built ${table} (root): '${BUILD_DIR}/${module_output}'"
	done
	# record what this app was built from (merged into build-state.txt on the update branch)
	digest="sha256:$(sha256sum "${args[ptjar]}" 2>/dev/null | cut -d' ' -f1)" || digest="-"
	[ -z "$(sha256sum "${args[ptjar]}" 2>/dev/null)" ] && digest="-"
	[ "$digest" = "sha256:" ] && digest="-"
	printf '%s|%s|%s|%s|%s|%s\n' "${args[table_key]}" "${args[patches_src]}" "-" "$(basename "${args[ptjar]}")" "$digest" "${args[version]}" >>"$TEMP_DIR/built-state.txt"
}

list_args() { tr -d '\t\r' <<<"$1" | tr -s ' ' | sed 's/" "/"\n"/g' | sed 's/\([^"]\)"\([^"]\)/\1'\''\2/g' | grep -v '^$' || :; }
join_args() { list_args "$1" | sed "s/^/${2} /" | paste -sd " " - || :; }

module_config() {
	local ma=""
	if [ "$4" = "arm64-v8a" ]; then
		ma="arm64"
	elif [ "$4" = "arm-v7a" ]; then
		ma="arm"
	fi
	echo "PKG_NAME=$2
PKG_VER=$3
MODULE_ARCH=$ma" >"$1/config"
}
module_prop() {
	echo "id=${1}
name=${2}
version=v${3}
versionCode=${NEXT_VER_CODE}
author=j-hc
description=${4}" >"${6}/module.prop"

	if [ "$ENABLE_MODULE_UPDATE" = true ]; then echo "updateJson=${5}" >>"${6}/module.prop"; fi
}
