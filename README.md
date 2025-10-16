# darktable-bootstrap-webgallery-export

The built-in webgallery-export in darktable does not meet my needs in terms of styling and function.
After some tests with a complicated lua-python script combo running outside darktable's export mechanism, I learned from Tino Mettler's new webgallery export ( https://discuss.pixls.us/t/new-website-gallery-storage-module-to-replace-photoswipe-written-in-lua/53354/16 ) how to achieve my goals in a much more straightforward way.

## Goals
  * Using boostrap for styling
  * Using a MIT licensed slideshow plugin, here http://ashleydw.github.io/lightbox/
  * Showing (adjustable) image titles, footers and location links
