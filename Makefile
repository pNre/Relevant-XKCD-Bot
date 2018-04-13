.PHONY: default all clean

default: all

all:
	jbuilder build @install
	@test -L bin || ln -s _build/install/default/bin .

clean:
	jbuilder clean
	git clean -dfXq
