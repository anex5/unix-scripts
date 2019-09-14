#!/bin/bash
base_dir=$( dirname "${BASH_SOURCE[0]}" )
source "${base_dir}/functions.sh"

work_dir=~
tmp_dir=/tmp
printf "\nThis script helps to install vim plugins"
execution_premission "install pathogen plugin (required)? " && {
	try mkdir -p ${work_dir}/.vim/autoload ${work_dir}/.vim/bundle
	try download https://tpo.pe/pathogen.vim ${work_dir}/.vim/autoload
	#curl -LSso ${work_dir}/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim #&& \
	#sed -n '/execute pathogen#infect()/p' ${work_dir}/.vimrc || echo -e "execute pathogen#infect()" >> ${work_dir}/.vimrc
} || die

execution_premission "install vinegar plugin? " && {
	git clone https://github.com/tpope/vim-vinegar.git ${work_dir}/.vim/bundle/vim-vinegar
}

execution_premission "install netrw plugin? " && {
	git clone https://github.com/eiginn/netrw.git ${work_dir}/.vim/bundle/netrw
}

execution_premission "install airline plugin? " && {
	git clone https://github.com/vim-airline/vim-airline ${work_dir}/.vim/bundle/vim-airline
}

execution_premission "install onedark colorscheme? " && {
	try mkdir -p ${tmp_dir}/onedark
	git clone https://github.com/joshdick/onedark.vim.git ${tmp_dir}/onedark
	try mkdir -p ${work_dir}/.vim/colors/
	cp ${tmp_dir}/colors/onedark.vim ${work_dir}/.vim/colors/
	try rm -r ${tmp_dir}/onedark
}

execution_premission "install molokai colorscheme? " && {
	try mkdir -p ${tmp_dir}/molokai
	git clone https://github.com/tomasr/molokai.git ${tmp_dir}/molokai
	try mkdir -p ${work_dir}/.vim/colors/
	cp ${tmp_dir}/colors/molokai.vim ${work_dir}/.vim/colors/
	try rm -r ${tmp_dir}/molokai
}