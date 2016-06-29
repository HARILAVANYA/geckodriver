set -ex

# Add provided target to current Rust toolchain if it is not already
# the default or installed.
rustup_target_add() {
	if ! rustup target list | grep -E "$1 \((default|installed)\)"
	then
		rustup target add $1
	fi
}

# Configure rustc target for cross compilation.  Provided with a build
# target, this will determine which linker to use for cross compilation.
cargo_config() {
	local prefix

	case "$TARGET" in
	aarch64-unknown-linux-gnu)
		prefix=aarch64-linux-gnu
		;;
	arm*-unknown-linux-gnueabihf)
		prefix=arm-linux-gnueabihf
		;;
	arm-unknown-linux-gnueabi)
		prefix=arm-linux-gnueabi
		;;
	mipsel-unknown-linux-musl)
		prefix=mipsel-openwrt-linux
		;;
	x86_64-pc-windows-gnu)
		prefix=x86_64-w64-mingw32
		;;
	*)
		return
		;;
	esac

	mkdir -p ~/.cargo
	cat >>~/.cargo/config <<EOF
[target.$TARGET]
linker = "$prefix-gcc"
EOF
}

# Build current crate for given target and print file type information.
# If the second argument is set, a release build will be made.
cargo_build() {
	local mode
	if [ -z "$2" ]
	then
		mode=debug
	else
		mode=release
	fi

	local modeflag
	if [ "$mode" == "release" ]
	then
		modeflag=--release
	fi
	
	cargo build --target $1 $modeflag

	file $(get_binary $1 $mode)
}

# Run current crate's tests if the current system supports it.
cargo_test() {
	if echo "$1" | grep -E "(i686|x86_64)-unknown-linux-(gnu|musl)"
	then
		cargo test --target $1
	fi
}

# Returns relative path to binary
# based on build target and type ("release"/"debug").
get_binary() {
	local ext
	if [[ "$1" =~ "windows" ]]
	then
		ext=".exe"
	fi
	echo "target/$1/$2/geckodriver$ext"
}

# Create a compressed archive of the binary
# for the given given git tag, build target, and build type.
package_binary() {
	local target
	case "$2" in
	armv7-unknown-linux-gnueabihf)
		target=arm7hf
		;;
	x86_64-pc-windows-gnu)
		target=win64
		;;
	x86_64-unknown-linux-musl)
		target=linux64
		;;
	esac

	local bin
	bin=$(get_binary $2 $3)
	cp $bin .

	if [[ "$2" =~ "windows" ]]
	then
		zip geckodriver-$1-$target.zip geckodriver.exe
		file geckodriver-$1-$target.zip
	else
		tar zcvf geckodriver-$1-$target.tar.gz geckodriver
		file geckodriver-$1-$target.tar.gz
	fi
}

# Create a compressed archive of the source code
# for the given git tag.
package_source() {
	git archive --format=tar --prefix="geckodriver-$1/" $1 | \
		gzip >geckodriver-$1.tar.gz
}

main() {
	rustup_target_add $TARGET

	cargo_config $TARGET
	cargo_build $TARGET
	cargo_test $TARGET

	# when something is tagged,
	# also create a release build and package it
	if [ ! -z "$TRAVIS_TAG" ]
	then
		cargo_build $TARGET 1
		package_binary $TRAVIS_TAG $TARGET "release"
		package_source $TRAVIS_TAG
	fi
}

main