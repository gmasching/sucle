(in-package :sucle)

;;;;************************************************************************;;;;
;;;;<BOXES?>
(defun create-aabb (&optional (maxx 1.0) (maxy maxx) (maxz maxx)
		      (minx (- maxx)) (miny (- maxy)) (minz (- maxz)))
  (floatf maxx maxy maxz minx miny minz)
  (aabbcc:make-aabb
   :minx minx
   :maxx maxx
   :miny miny
   :maxy maxy
   :minz minz
   :maxz maxz))

(defparameter *block-aabb*
  ;;;;1x1x1 cube
  (create-aabb 1.0 1.0 1.0 0.0 0.0 0.0))

;;;;[FIXME]The point of this is to reduce the amount of bits to store the hitbox.
;;;;Why? because when there is an inexact number, like 0.3, there are bits at the end which
;;;;get chopped off or something, thus leading to strange clipping.
;;;;This effectively reduces the precision, giving leeway for math operations.
;;;;My prediction could be wrong though.
(defun round-to-nearest (x &optional (n (load-time-value (/ 1.0 128.0))))
  (* n (round (/ x n))))
(defparameter *player-aabb*
  (apply #'create-aabb
	 (mapcar 'round-to-nearest	 
		 '(0.3 0.12 0.3 -0.3 -1.5 -0.3))))

;;;a very small cubic fist
(defparameter *fist-aabb* (create-aabb 0.00005))

(defparameter *chunk-aabb*
  (apply 'create-aabb
	 (mapcar 'floatify
		 (list vocs:+size+ vocs:+size+ vocs:+size+ 0.0 0.0 0.0))))
(defparameter *start-menu*
  `(;;keys bound to functions
    (((:key :pressed #\f) .
      ,(lambda () (print "Paying Respects")))
     ((:key :pressed #\q) .
      ,(lambda () (app:quit)))
     ((:key :pressed #\Escape) .
      ,(lambda () (app:quit)))
     ((:key :pressed #\p) .
      ,(lambda () (app:pop-mode)))
     ((:key :pressed #\o) .
      ,(lambda () (app:push-mode 'menu:tick)))
     ((:key :pressed #\s) .
      ,(lambda ()
	 (app:push-mode 'sucle-per-frame)))
     ((:key :pressed #\c) .
      ,(lambda ()
	 (print "Clearing...")
	 (let ((clear (assoc :clear menu:*data*)))
	   (setf (second clear)
		 (with-output-to-string (str)
		   (let ((clearstr
			  (make-string menu:*w*
				       :initial-element #\space)))
		     (dotimes (y menu:*h*)
		       (terpri str)
		       (write-string clearstr str))))))))
     ((:key :released #\c) .
      ,(lambda ()
	 (print "Clearing Done!")
	 (let ((clear (assoc :clear menu:*data*)))
	   (setf (second clear)
		 "")))))
    ;;data to render
    ((:hello
      "
Press s to start the game

Press c to clear

Press h for help

Press F to pay respects [not really]

Press q/escape to quit
" 4 4 :bold t)
     ;;(:hello "world" 8 16 :fg "green" :bg "red" :reverse t :bold t)
     (:clear "" 0 0  :bold t))
    ()))

;;;;</BOXES?>
(defparameter *some-saves* nil)
(defparameter *world-directory* nil)
(defun world-path
    (&optional
       (world
	;;"first/"
	;;#+nil
	;;"test/"
	"other/"
	;;"third/"
	;;"terrarium2/"
	;;"ridikulisp/"
	)
       (working-dir
	(sucle-temp:path "save/")
	#+nil
	(cdr (assoc (machine-instance) 
		    '(("gm3-iMac" . #P"/media/imac/share/space/lispysaves/saves/sandbox-saves/")
		      ("nootboke" . #P"/home/terminal256/Documents/saves/"))
		    :test 'equal))))
  (utility:rebase-path world working-dir))
(defun start ()
  (app:enter 'sucle-app))

(defun sucle-app ()
  #+nil
  (setf (entity-fly? *ent*) nil
	(entity-gravity? *ent*) t)
  ;;(our-load)
  (window:set-vsync t)
  (fps:set-fps 60)
  (ncurses-clone-for-lem:init)
  (app:push-mode 'menu:tick)
  (menu:use *start-menu*)
  (crud:use-crud-from-path
   ;;(sucle-temp:path "data.db")
   ;;(world-path)
   ;;(sucle-temp:path "new.db")
   (sucle-temp:path "test.db")
   )
  (sucle-mp:with-initialize-multiprocessing
   (unwind-protect (app:default-loop)	  
     (when vocs::*persist*
       (vocs::save-all)))))

;;;;

#+nil
(defun start ()
  (application:main
   (lambda ()
     (call-with-world-meshing-lparallel 
      (lambda ()
	(loop
	   (application:poll-app)
	   (per-frame)))))
   :width 720
   :height 480
   :title "conceptually simple block game"))

;;;;************************************************************************;;;;
;;;;This code basically has not changed in forever.

(defparameter *raw-mouse-x* 0.0d0)
(defparameter *raw-mouse-y* 0.0d0)
(defun cursor-motion-difference
    (&optional (x window:*mouse-x*) (y window:*mouse-y*))
  ;;Return the difference in position of the last time the
  ;;cursor was observed.
  ;;*raw-mouse-x* and *raw-mouse-y* hold the last value
  ;;of the cursor.
  (multiple-value-prog1
      (values (- x *raw-mouse-x*)
	      (- y *raw-mouse-y*))
    (setf *raw-mouse-x* x
	  *raw-mouse-y* y)))

(defparameter *mouse-x* 0.0d0)
(defparameter *mouse-y* 0.0d0)
(defparameter *lerp-mouse-x* 0.0d0)
(defparameter *lerp-mouse-y* 0.0d0)
(defun update-moused (clamp &optional (smoothing-factor 1.0))
  (multiple-value-bind (dx dy) (cursor-motion-difference)
    (let ((x (+ *mouse-x* dx))
	  (y (+ *mouse-y* dy)))
      ;;So looking straight up stops.
      (when (> y clamp)
	(setf y clamp))
      ;;So looking straight down stops
      (let ((negative (- clamp)))
	(when (< y negative)
	  (setf y negative)))
      (setf *mouse-x* x)
      (setf *mouse-y* y)))
  ;;*lerp-mouse-x* and *lerp-mouse-y* are used
  ;;for camera smoothing with the framerate.
  (setf *lerp-mouse-x* (alexandria:lerp smoothing-factor *lerp-mouse-x* *mouse-x*))
  (setf *lerp-mouse-y* (alexandria:lerp smoothing-factor *lerp-mouse-y* *mouse-y*)))
(defparameter *mouse-multiplier* 0.002617)
(defparameter *mouse-multiplier-aux* (/ (* 0.5 pi 0.9999) *mouse-multiplier*))
(defun neck-values ()
  (values
   (floatify (* *lerp-mouse-x* *mouse-multiplier*))
   (floatify (* *lerp-mouse-y* *mouse-multiplier*))))

(defun unit-pitch-yaw (pitch yaw &optional (result (sb-cga:vec 0.0 0.0 0.0)))
  (setf yaw (- yaw))
  (let ((cos-pitch (cos pitch)))
    (with-vec (x y z) (result symbol-macrolet)
      (setf x (* cos-pitch (sin yaw))
	    y (- (sin pitch))
	    z (* cos-pitch (cos yaw)))))
  result)

;;;;************************************************************************;;;;
;;emacs-like modes
(defparameter *active-modes* ())
(defun reset-all-modes ()
  (setf *active-modes* nil))
(defun enable-mode (mode)
  (pushnew mode *active-modes* :test 'equal))
(defun disable-mode (mode)
  (setf *active-modes* (delete mode *active-modes*)))
(defun mode-enabled-p (mode)
  (member mode *active-modes* :test 'equal))
(defun set-mode-if (mode p)
  (if p
      (enable-mode mode)
      (disable-mode mode)))
;;;;************************************************************************;;;;

(defparameter *session* nil)
(defparameter *ticks* 0)
(defparameter *game-ticks-per-iteration* 0)
(defparameter *fraction-for-fps* 0.0)
(defparameter *fist* nil)
(defparameter *entities* nil)
(defparameter *ent* nil)
(defparameter *reach* 50.0)
(defparameter *fov* (floatify (* pi (/ 85 180))))
(defparameter *camera*
  (camera-matrix:make-camera
   :frustum-far (* 256.0)
   :frustum-near (/ 1.0 8.0)))
(defparameter *fog-ratio* 0.75)
(defparameter *time-of-day* 1.0)
(defparameter *sky-color*
  (mapcar 'utility:byte/255
	  ;;'(0 0 0)
	  '(173 204 255)))
(defun atmosphere ()
  (let ((sky (mapcar 
	      (lambda (x)
		(alexandria:clamp (* x *time-of-day*) 0.0 1.0))
	      *sky-color*))
	(fog *fog-ratio*))
    (values
     (mapcar
      (lambda (a b)
	(alexandria:lerp *fade* a b))
      *fade-color*
      sky)
     (alexandria:lerp *fade* 1.0 *fog-ratio*))))
(defparameter *fade-color* '(0.0 0.0 0.0))
(defparameter *fade* 1.0)

(defun update-world-vao2 ()
  (update-world-vao
   (lambda (key)
     (world:unsquared-chunk-distance
      key
      (vocs::cursor-x *chunk-cursor-center*)
      (vocs::cursor-y *chunk-cursor-center*)
      (vocs::cursor-z *chunk-cursor-center*)))))
;;*frame-time* is for graphical frames, as in framerate.
(defparameter *frame-time* 0)
(defun sucle-per-frame ()
  (incf *frame-time*)
  ;;[FIXME]where is the best place to flush the job-tasks?
  (sucle-mp:flush-job-tasks)
  ;;set the chunk center aroun the player
  (livesupport:update-repl-link)
  (application:on-session-change *session*
    (voxel-chunks:clearworld)
    (pushnew
     *chunk-cursor-center*
     voxel-chunks::*pinned-cursors*)
    ;;Comes after 'clearworld' because 'clearworld'
    ;;resets the chunk-array
    (setf (vocs::cursor-chunk-array *chunk-cursor-center*)
	  vocs::*chunk-array*)
    (let ((player (entity:create-player-entity)))
      (setf *entities* (cons player
                             (loop :repeat 10 :collect (entity:create-dumb-entity))))
      (setf *ent* player))
    (sync_entity->chunk-array *ent* *chunk-cursor-center*)
    (load-world *chunk-cursor-center*;; t
		)
    ;;Controller?
    (reset-all-modes)
    (enable-mode :normal-mode)
    (enable-mode :god-mode)
    ;;Model
    ;;FIXME::this depends on the position of entity.
    ;;Rendering/view?
    (reset-chunk-display-list)
    (update-world-vao2))
  (sync_entity->chunk-array *ent* *chunk-cursor-center*)
  ;;load or unload chunks around the player who may have moved
  (load-world *chunk-cursor-center*)
  ;;Polling
  ;;Physics
  ;;Rendering Chunks
  ;;Rendering Other stuff
  ;;Meshing
  ;;Waiting on vsync
  ;;Back to polling
  
  ;;Physics and Polling should be close together to prevent lag
  
  ;;physics

  ;;Calculate what bocks are selected etc..
  ;;#+nil
  (setf *fist*
	(mvc 'standard-fist
	     (spread (entity:pos *ent*))
	     (spread (sb-cga:vec*
		      (camera-matrix:camera-vec-forward *camera*)
		      *reach*))))
  (when (mode-enabled-p :fist-mode)
    (run-buttons *fist-keys*))
  (when (mode-enabled-p :god-mode)
    (run-buttons *god-keys*))
  (when (mode-enabled-p :movement-mode)
    ;;Set the sneaking state
    (setf (entity:sneak-p *ent*)
	  (cond
	    ((window:button :key :down :left-shift)
	     0)
	    ((window:button :key :down :left-control)
	     1)))
    ;;Jump if space pressed
    (setf (entity:jump-p *ent*)
	  (window:button :key :down #\Space))
    #+nil
    (when (window:button :key :pressed #\Space)
      (set-doublejump *ent*))
    ;;Set the direction with WASD
    (setf
     (entity:direction *ent*)
     (let ((x 0)
	   (y 0))
       (when (window:button :key :down #\w)
	 (incf x))
       (when (window:button :key :down #\s)
	 (decf x))
       (when (window:button :key :down #\a)
	 (decf y))
       (when (window:button :key :down #\d)
	 (incf y))
       ;;[FIXME]
       ;;This used to be cached and had its own function in
       ;;the control.asd
       (if (and (zerop x)
		(zerop y))
	   nil			   
	   (floatify (atan y x)))))
    ;;update the internal mouse state
    ;;taking into consideration fractions
    (update-moused *mouse-multiplier-aux* 1.0))
  (when (mode-enabled-p :normal-mode)
    ;;[FIXME] because this runs after update-moused, the camera swivels
    ;;unecessarily.
    (run-buttons *normal-keys*))
  (let ((number-key (control:num-key-jp :pressed)))
    (when number-key
      (setf *ent* (elt *entities* number-key))))
  
  ;;Set the pitch and yaw of the player based on the
  ;;mouse position
  ;; (mvc 'set-neck-values (entity-neck *ent*) (neck-values))
  (multiple-value-bind (yaw pitch) (neck-values)
    (setf (entity:neck-yaw *ent*) yaw
          (entity:neck-pitch *ent*) pitch))

  ;;Run the game ticks

  ;;FIXME:: run fps:tick if resuming from being paused.
  (setf
   (values *fraction-for-fps* *game-ticks-per-iteration*)
   (fps:tick 
     (incf *ticks*)
     (setf *time-of-day* 1.0)
     ;;run the physics
     ;; (entity:step-physics *ent* (fps:dt))
     (mapcar (lambda (ent)
               (entity:step-physics ent (fps:dt))
               (entity:run-ai ent (fps:dt)))
             *entities*)
     (entity::run-particles (fps:dt))))
  ;;render chunks and such
  ;;handle chunk meshing
  (sync_entity->camera *ent* *camera*)

  (get-chunks-to-draw
   (let ((ent (elt *entities* 0))
         (camera (camera-matrix:make-camera)))
     (sync_entity->camera ent camera)
     camera)
   (vocs::cursor-radius *chunk-cursor-center*)
   (vocs::cursor-x *chunk-cursor-center*)
   (vocs::cursor-y *chunk-cursor-center*)
   (vocs::cursor-z *chunk-cursor-center*))
  
  (draw-to-default-area)
  ;;this also clears the depth and color buffer.
  (multiple-value-bind (color fog) (atmosphere)
    (let ((radius (vocs::cursor-radius *chunk-cursor-center*))
	  (darkness (* *fade* *time-of-day*)))
      (apply #'render-sky color)
      (use-chunk-shader
       :camera *camera*
       :sky-color color
       :time-of-day darkness
       :fog-ratio fog
       :chunk-radius radius)
      ;; #+nil
      (map nil
	   (lambda (ent)
	     (unless (eq ent *ent*)
	       (render-entity ent)))
	   *entities*)
      (render-chunks)
      (use-particle-shader
       :camera *camera*
       :sky-color color
       :time-of-day darkness
       :fog-ratio fog
       :chunk-radius radius
       :sampler (glhelp:handle (deflazy:getfnc 'terrain))) 
      (render-particles)))
  
  (use-occlusion-shader *camera*)
  (render-chunk-occlusion-queries)
  ;;selected block and crosshairs
  (use-solidshader *camera*)
  (render-fist *fist*)
  ;;#+nil
  (progn
    (gl:line-width 10.0)
    (map nil
	 (lambda (ent)
	   (when (eq ent (elt *entities* 0))
	     (let ((*camera* (camera-matrix:make-camera)))
	       (sync_entity->camera ent *camera*)
	       (render-camera *camera*))))
	 *entities*))
  #+nil
  (progn
    (gl:line-width 10.0)
    (render-chunk-outlines))
  ;;#+nil
  (progn
    (gl:line-width 10.0)
    (render-units))
  ;;(mvc 'render-line 0 0 0 (spread '(200 200 200)))
  (render-crosshairs)
  
  (complete-render-tasks)
  (dispatch-mesher-to-dirty-chunks
   (vocs::cursor-x *chunk-cursor-center*)
   (vocs::cursor-y *chunk-cursor-center*)
   (vocs::cursor-z *chunk-cursor-center*)))

;;[FIXME]architecture:one center, the player, and the chunk array centers around it
(defparameter *chunk-cursor-center* (vocs::make-cursor))
(defun sync_entity->chunk-array (ent cursor)
  (mvc 'vocs::set-cursor-position
       (spread (entity:pos ent))
       cursor))

(defun load-world (chunk-cursor-center)
  (let ((maybe-moved (vocs::cursor-dirty chunk-cursor-center)))
    (when maybe-moved
      (mapc 'world::dirty-push-around (vocs::load-chunks-around *chunk-cursor-center*)))
    (vocs::call-fresh-chunks-and-end
     (lambda (chunk)
       ;;FIXME:this does not load the nearest chunks to render first?
       ;;fresh-chunks are not necessarily fresh. reposition-chunk array gets rid of
       ;;everything when moving, how to only update those that exist?
       (world::dirty-push (vocs::chunk-key chunk))))
    (when maybe-moved
      (setf (vocs::cursor-dirty chunk-cursor-center) nil))))

(defun render-particles ()
  (gl:disable :cull-face)
  (dolist (particle entity::*particles*)
    (mvc 'render-particle-at
	 (spread (entity::pos particle))
	 (entity::particle-uv particle))))

(defun render-chunk-outlines ()
  (dohash (k chunk) *g/chunk-call-list*
	  (declare (ignorable v))
	  (render-aabb-at
	   (chunk-gl-representation-aabb chunk)
	   0.0 0.0 0.0)))

(defun render-camera (camera)
  (mapc (lambda (arg)
	  (mvc 'render-line-dx
	       (spread (camera-matrix:camera-vec-position camera))
	       (spread (map 'list
			    (lambda (x)
			      (* x 100))
			    arg))))
	(camera-matrix::camera-edges camera))
  (mapc (lambda (arg)
	  (mvc 'render-line-dx
	       (spread (camera-matrix:camera-vec-position camera))
	       (spread (map 'list
			    (lambda (x)
			      (* x 100))
			    arg))
	       0.99 0.8 0.0))
	(camera-matrix::camera-planes camera)))

(defun render-units (&optional (foo 100))
  ;;X is red
  (mvc 'render-line 0 0 0 foo 0 0 (spread #(1.0 0.0 0.0)))
  ;;Y is green
  (mvc 'render-line 0 0 0 0 foo 0 (spread #(0.0 1.0 0.0)))
  ;;Z is blue
  (mvc 'render-line 0 0 0 0 0 foo (spread #(0.0 0.0 1.0))))

(defun sync_entity->camera (entity camera)
  ;;FIXME:this lumps in generating the other cached camera values,
  ;;and the generic used configuration, such as aspect ratio and fov.
  
  ;;Set the direction of the camera based on the
  ;;pitch and yaw of the player
  (sync_neck->camera (entity:neck-pitch entity)
                     (entity:neck-yaw entity)
                     camera)
  ;;Calculate the camera position from
  ;;the past, current position of the player and the frame fraction
  (sync_position->camera
   ;;modify the camera for sneaking
   (entity:pos entity)
   (entity:pos-old entity)

   #+nil(let ((particle (entity-particle entity)))
          (if (and (not (entity:fly-p entity))
                   (eql 0 (entity:sneak-p entity)))
              (translate-pointmass particle 0.0 -0.125 0.0)
              particle))
   camera
   *fraction-for-fps*)
  ;;update the camera
  ;;FIXME::these values are
  (set-camera-values
   camera
   (/ (floatify window:*height*)
      (floatify window:*width*)
      )
   *fov*
   (* 1024.0 256.0)
   )
  (camera-matrix:update-matrices camera)
  ;;return the camera, in case it was created.
  (values camera))
(defun set-camera-values (camera aspect-ratio fov frustum-far)
  (setf (camera-matrix:camera-aspect-ratio camera) aspect-ratio)
  (setf (camera-matrix:camera-fov camera) fov)
  (setf (camera-matrix:camera-frustum-far camera) frustum-far))
(defun sync_position->camera (curr prev camera fraction)
  (let ((vec (camera-matrix:camera-vec-position camera)))
    (nsb-cga:%vec-lerp vec prev curr fraction)))
(defun sync_neck->camera (pitch yaw camera)
  #+nil
  (print (list (necking-pitch neck)
	       (necking-yaw neck)))
  ;;(print)
  (unit-pitch-yaw pitch 
                  yaw                  
                  (camera-matrix:camera-vec-forward camera)))

;;;;************************************************************************;;;;

(defparameter *blockid* (block-data:lookup :planks))
(defparameter *x* 0)
(defparameter *y* 0)
(defparameter *z* 0)
;;;detect more entities
;;;detect block types
;;;;Default punching and placing blocks
(defparameter *left-fist* 'destroy-block-at)
(defun destroy-block-at (&optional (x *x*) (y *y*) (z *z*))
  ;;(blocksound x y z)
  (shoot-particles (+ 0.5 x) (+ 0.5 y) (+ 0.5 z) (world:getblock x y z))
  (world:plain-setblock x y z (block-data:lookup :air) 15))
(defparameter *right-fist* 'place-block-at)
(defun place-block-at (&optional (x *x*) (y *y*) (z *z*) (blockval *blockid*))
  (when (entity::not-occupied *ent* x y z)
    ;;(blocksound x y z)
    (world:plain-setblock x y z blockval (block-data:data blockval :light))))

(defparameter *5-fist* (constantly nil))
(defparameter *4-fist* (constantly nil))
(defparameter *middle-fist* (constantly nil))
(defparameter *fist-keys*
  `(((:mouse :pressed :left) . 
     ,(lambda ()
	(when (fist-exists *fist*)
	  (multiple-value-bind (*x* *y* *z*) (spread (fist-selected-block *fist*))
	    (funcall *left-fist*)))))
    ((:mouse :pressed :right) .
     ,(lambda ()
	(when (fist-exists *fist*)
	  (multiple-value-bind (*x* *y* *z*) (spread (fist-normal-block *fist*))
	    (funcall *right-fist*)))))

    ((:mouse :pressed :5) . 
     ,(lambda ()
	;;(when (fist-exists *fist*))
	(multiple-value-bind (*x* *y* *z*) (spread (fist-selected-block *fist*))
	  (funcall *5-fist*))))
    ((:mouse :pressed :4) . 
     ,(lambda ()
	;;(when (fist-exists *fist*))
	(multiple-value-bind (*x* *y* *z*) (spread (fist-selected-block *fist*))
	  (funcall *4-fist*))))
    ((:mouse :pressed :middle) . 
     ,(lambda ()
	(when (fist-exists *fist*)
	  (multiple-value-bind (*x* *y* *z*) (spread (fist-selected-block *fist*))
	    (funcall *middle-fist*)))))))
(defparameter *normal-keys*
  `(((:key :pressed #\p) .
     ,(lambda () (update-world-vao2)))
    ((:key :pressed :escape) .
     ,(lambda ()
	(window:get-mouse-out)
	(app:pop-mode)))
    ((:key :pressed #\e) .
     ,(lambda ()
	(window:toggle-mouse-capture)
	(set-mode-if :movement-mode (not (window:mouse-free?)))
	(set-mode-if :fist-mode (not (window:mouse-free?)))
	;;Flush changes to the mouse so
	;;moving the mouse while not captured does not
	;;affect the camera
	;;FIXME::not implemented.
	;;(moused)
	))))
(defparameter *god-keys*
  `(;;Toggle noclip with 'v'
    ((:key :pressed #\v) .
     ,(lambda () (toggle (entity:fly-p *ent*))))
    ;;Toggle flying with 'f'
    ((:key :pressed #\f) .
     ,(lambda () (toggle (entity:fly-p *ent*))
         (toggle (entity::gravity-p *ent*))))))

;;;

(defun random-in-range (n)
  (* (random n) (if (zerop (random 2))
		    1
		    -1)))
(defun shoot-particles
    (&optional
       (x (random-in-range 20.0))      
       (y (random 30.0))
       (z (random-in-range 20.0))
       (id 3))
  (dotimes (i 10)
    (let ((direction
	   (sucle::unit-pitch-yaw (- (random (floatify pi)))
				  (random (floatify pi)))))
      (mvc 'entity::create-particle id x y z
	   (spread
	    (ng:vec* direction (random 20.0)))
	   (+ 1 (random 1.0))))))
