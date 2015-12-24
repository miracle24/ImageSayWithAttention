------------------------------------
----------- Author @ LC ------------
------------------------------------

--require("mobdebug").start()
require 'hdf5' -- read .h5 file format
require 'torchx' -- for paths.indexdir
require 'lfs'

---------------------------------------------------------------------------
--- First, let's try to convert the Flickr8k dataset into dp.dataset format
--- Don't know how to deal with the sentence yet.
--- Should the sentence be dealt as multi-labels? Or ?
---------------------------------------------------------------------------

local Flickr8k = torch.class("Flickr8k") -- customize class
--local utils_path = lfs.currentdir()..'/misc/utils.lua;'
--package.path = '../misc/utils.lua;' .. package.path
--package.path = utils_path..package.path
--print (package.path)
--require 'utils' -- utility functions

----------------------------------------------------------
--- Initialize function, does the following:
---	1. Load the images (prepared, resized) info 
---	2. Load the sentences (numbered), and ix_to_word
---	3. Arrange those info into a flickr8k table
-----------------------------------------------------------
function Flickr8k:__init(datapath)
    -- 1. load the images, and the caption sentences
    -- pre-prepared with neuraltalk2/prepo.py, to create lua-readable data

    -- data.h5 file format:
    --  -> 'images': (100, 3, 256, 256), contains 100 resized (3x256x256) images. Note: image 100 is black??
    --	-> 'label_end_ix': 1-indexed numbers, 1-100, no idea what it is for, for now.
    --	-> 'label_length': the sentence length of each image captioned
    --	-> 'label_start_ix': again, 1-indexed numbers, 1-100, no idea what it is for 
    --	-> 'labels': (100, 16), 100 images; 16 as the longest sentence;
    --	->	    each containes a sequence of numbers, representing the numbered word 
    -- #TODO: add assertion to make sure file exists
    print ('Loading flickr8k data.h5 file ...')
    h5_file_path = datapath..'/'..'data.h5'
    if utils.exists(h5_file_path) then print ('Done.') else return end -- check whether file exists
    local h5_file = hdf5.open(h5_file_path)
    local images = h5_file:read('/images'):all() -- read all 100 images, access via images[i] for image i
    local sentences = h5_file:read('/labels'):all() -- read all 100 sentences, access via sentences[i] for image i
    h5_file:close()

    -- 2. load the word-number mapping json file
    -- pre-prepared with neuraltalk2/prepo.py

    -- data.json file format:
    --	-> 'images': containes info of the 100 images, 100 x {'flie_path', 'split'}
    --	     -> 'file_path': string, the filename, eg. '1597557856_30640e0b43.jpg'
    --	     -> 'split': string, 'train', 'validation', or 'test' split
    --	-> 'ix_to_word': the mapping from number to word, eg. 101 is 'cigarettes' 
    -- #TODO: add assertion to make sure file exists
    print ('Loading flickr8k data.json file ...')
    json_file_path = datapath..'/'..'data.json'
    if utils.exists(json_file_path) then print ('Done.') else return end -- check whether file exists
    local json_file = io.open(json_file_path)
    local text = json_file:read()
    local cjson = require 'cjson' -- read .json file format
    local json_file_contents = cjson.decode(text)
    local ix_to_word = json_file_contents.ix_to_word
    local images_info = json_file_contents.images
    json_file:close()

    -- put the images, sentences, images_info, and ix_to_word all together into a flickr8k dataset
    self._flickr8k = {images, sentences, images_info, ix_to_word}
    return self._flickr8k 
end


-------------------------------------------------------
--- Prepare Flickr8k into dp dataset
-------------------------------------------------------

function Flickr8k:setup()
    self._train = Flickr8k:_setup_train() -- setup train
    self._valid = Flickr8k:_setup_valid() -- setup valid
    self._test = Flickr8k:_setup_test() -- setup test 
end

-------------------------------------------------------
--- Prepare Flickr8k into dp dataset format for train
-------------------------------------------------------

function Flickr8k:_setup_train()
    local flickr8k = self._flickr8k
    local images_info = flickr8k[ 

end

-------------------------------------------------------
--- Prepare Flickr8k into dp dataset format for valid
-------------------------------------------------------

function Flickr8k:_setup_valid()
end



-------------------------------------------------------
--- Prepare Flickr8k into dp dataset format for test
-------------------------------------------------------

function Flickr8k:_setup_test()
end




----------------------------------------------------
--- show basic information of image[id], including:
---	1. display the image	
---	2. the file_path and the split 
---	3. ix_to_word codes of the sentences
---	4. the decoded sentence 
--- #TODO: how to close the displayed image normally?
----------------------------------------------------
function Flickr8k:showImg(id)
    print ('---------------------------------------------------------------')
    local str = string.format('---- info of image %d -----', id)
    print (str)
    local flickr8k = self._flickr8k
    --print (flickr8k[1][id]) 
    local image = require 'image'
    image.display(flickr8k[1][id]) -- first [1]: the images field of flickr8k; second [1]: the first image of the images
    print ()
    print ('---- File name:', flickr8k[3][id]['file_path']) 
    print ('---- Split:', flickr8k[3][id]['split']) 

    for i = 1, (flickr8k[2][id]):size()[1] do -- :size()[1] makes sure it is a number rather than a torch.LongStorage of size 1
	local word = flickr8k[2][id][i]
	if word ~= nil then io.write (word,' ') end
    end
    print ()
    -- let's try to print the caption sentence for image[1]
    for i = 1, (flickr8k[2][id]):size()[1] do
	local word_int = flickr8k[2][id][i] -- word i in sentence of image[1]
	local word_str = string.format("%d", word_int) -- convert int to string, using string.format function
	local word = flickr8k[4][word_str]
	if word ~= nil then io.write (word, ' ') end
    end
    print ('.')
    print ('---------------------------------------------------------------')
end
function Flickr8k:show()
    require "image"
    image.display(image.lena())
end


