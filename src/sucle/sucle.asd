(asdf:defsystem #:sucle
  :author "terminal625"
  :license "MIT"
  :description "Cube Demo Game"
  :depends-on
  (
   #:application
   #:alexandria  
   #:utility 
   #:sucle-temp ;;for the terrain picture 
   #:text-subsystem
   #:cl-opengl
   #:glhelp
   #:scratch-buffer
   #:nsb-cga
   #:camera-matrix
   #:quads
   #:sucle-multiprocessing
   #:aabbcc ;;for occlusion culling 
   #:image-utility
   #:uncommon-lisp
   #:fps-independent-timestep
   #:control
   #:alexandria  
   #:ncurses-clone-for-lem
   #:livesupport
   
   #:crud
   
   #:sha1
   #:patchwork)
  :serial t
  :components 
  (
   (:file "queue")
   (:file "voxel-chunks")
   (:file "package")
   (:file "util")
   (:file "menu")
   ;;(:file "block-light") ;;light propogation
   (:file "mesher")
   (:file "spritepacker")
   (:file "block-data")
   (:file "world")
   (:file "fist")
   (:file "physics")
   (:file "ai")
   (:file "entity")
   (:file "sucle")
   (:file "render")))
