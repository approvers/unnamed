# vim: ft=make

# starts dev container
dev:
	docker build -t unnamed-dev .
	docker run -it --rm \
		--name unnamed-dev \
		--volume {{justfile_directory()}}/lua:/home/john/.config/nvim/lua \
		unnamed-dev bash

# attach to container which is already started.
attach:
	docker exec -it unnamed-dev bash

# format lua files using stylua
# install by `cargo install stylua` if you have not installed
fmt:
	stylua .
