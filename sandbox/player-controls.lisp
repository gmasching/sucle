(in-package :sandbox)

;;;;150 ms delay for sprinting
;;;;player eye height is 1.5, subtract 1/8 for sneaking

;;gravity is (* -0.08 (expt tickscale 2)) 0 0
;;falling friction is 0.98
;;0.6 * 0.91 is walking friction

;;fov::
;;70 is normal
;;110 is quake pro

(defparameter float-pi (coerce pi 'single-float))
(defun rad-deg (rad)
  (* rad (/ 180.0 float-pi)))
(defun deg-rad (deg)
  (* deg (/ float-pi 180.0)))

(defparameter *yaw* 0.0)
(defparameter *pitch* 0.0)
(defparameter *xpos* 0.0)
(defparameter *ypos* 0.0)
(defparameter *zpos* 0.0)
(defparameter *xpos-old* 0.0)
(defparameter *ypos-old* 0.0)
(defparameter *zpos-old* 0.0)
(defparameter defaultfov (deg-rad (and 95 70)))

(defparameter *xvel* 0.0)
(defparameter *yvel* 0.0)
(defparameter *zvel* 0.0)

(defparameter air-friction 0.98)
(defparameter walking-friction (prog2 0.93 (* 0.6 0.9)))

(defparameter noclip nil)
(defparameter gravity nil)
(defparameter fly t)

(defparameter *hotbar-selection* 3)

(defparameter onground nil)

(defparameter fist-side-x nil)
(defparameter fist-side-y nil)
(defparameter fist-side-z nil)

(defparameter fist? nil)
(defparameter fist-side nil)
(defparameter fistx 0.0)
(defparameter fisty 0.0)
(defparameter fistz 0.0)

(defparameter reach 4.0)

(setf *xpos* 0.0
      *ypos* 0.0
      *zpos* 0.0
      *yaw* 0.0
      *pitch* 0.0)

(eval-always
 (import (quote (e::skey-p e::skey-j-p e::skey-j-r e::keyval e::mouseval))))

(defun controls (control-state)
  (setf net-scroll (alexandria:clamp (+ net-scroll e:*scroll-y*) -1.0 1.0))
  (let ((speed (prog2 0.03 (* 0.4 (expt tickscale 2)))))
    (when fly
      (setf speed 0.024)
      (when (skey-p (keyval :space) control-state)
	(incf *yvel* speed))
      (when (skey-p (keyval :left-shift) control-state)
	(decf *yvel* speed)))
    (unless fly
      (when onground
	(when (skey-p (keyval :space) control-state) ;;jumping
	  (incf *yvel* (prog2 0.32 (* 
			    (if t 0.49 0.42) (expt tickscale 1))))))
      (unless onground
	(setf speed (* speed 0.2))))    
    (let ((dir (complex 0 0)))
      (when (skey-p (keyval :w) control-state) ;;w
	(incf dir #C(-1 0)))
      (when (or (skey-p (keyval :a) control-state)) ;;a
	(incf dir #C(0 1)))
      (when (skey-p (keyval :s) control-state) ;;s
	(incf dir #C(1 0)))
      (when (or (skey-p (keyval :d) control-state)) ;;d
	(incf dir #C(0 -1)))
      #+nil
      (when (not (or fly onground))
	(setf speed 0.001))
      (unless (zerop dir)
	(let ((rot-dir (* dir (cis *yaw*))))
;;	  (print (type-of rot-dir))
	  (let ((normalized (/ rot-dir ((lambda (x)
					  (declare (optimize (speed 3) (safety 0))
						   (type (complex single-float) x))
					  (abs x))
					rot-dir))))
	    (incf *xvel* (* speed (realpart normalized)))
	    (incf *zvel* (* speed (imagpart normalized)))))))
    (progno
     (let ((speed (* net-scroll -0.002)))
       (incf *xvel* (* speed look-x))
       (incf *yvel* (* speed look-y))
       (incf *zvel* (* speed look-z))))))

(defparameter mouse-sensitivity (coerce (* 60.0 pi 1/180) 'single-float))
(defconstant two-pi (coerce (* 2 pi) 'single-float))
(defconstant half-pi (coerce (/ pi 2) 'single-float))


(progn
  (declaim (ftype (function (single-float) single-float)
		  translator))
  (fuktard::with-unsafe-speed
    (defun translator (x)
      (let* ((a (* x 0.6))
	     (b (+ 0.2 a))
	     (c (* b b b))
	     (d (* 8.0 0.15 (/ (coerce pi 'single-float) 180.0)))
	     (e (* d c)))
	(declare (type single-float a b c d e))
	e))))

(defun look-around ()
  (multiple-value-bind (dx dy) (delta)
    (let ((dyaw (* dx (translator 0.5)))
	  (dpitch (* dy (translator 0.5))))
      (unless (zerop dyaw)
	(setf *yaw* (mod (+ *yaw* dyaw) two-pi)))
      (unless (zerop dpitch)
	(setf *pitch* (alexandria:clamp
		       (+ *pitch* dpitch)
		       (* -0.99 half-pi)
		       (* 0.99 half-pi)))))))

(defun delta ()
  (let ((mouse-data (load-time-value (cons 0 0))))
    (multiple-value-bind (newx newy) (window:get-mouse-position)
      (multiple-value-prog1 (values
			     (- newx (car mouse-data))
			     (- newy (cdr mouse-data)))
	(setf (car mouse-data) newx
	      (cdr mouse-data) newy)))))

(defparameter mousecapturestate nil)
(defun remove-spurious-mouse-input ()
  (if (window:mice-locked-p)
      (case mousecapturestate
	((nil)
	 (delta) ;;toss spurious mouse movement 
	 (setf mousecapturestate :justcaptured))
	(:justcaptured (setq mousecapturestate t))
	((t)))
      (when mousecapturestate
	(setq mousecapturestate nil))))

(defun hotbar-add (num)
  (setf *hotbar-selection* (truncate (mod (+ num *hotbar-selection*) 256))))

(defparameter daytime 1.0)
(defparameter ticks/sec nil)
(defparameter tickscale nil)
(defparameter tick-delay nil)

(world:setup-hashes)

(defun physinnit ()
  (clean-dirty)
  (setf ticks/sec 60.0)
  (setf tickscale (/ 20.0 ticks/sec))
  (setf tick-delay (/ 1000000.0 ticks/sec)))

(defparameter net-scroll 0)

(defparameter walkblock nil)
(defparameter foo nil)

(progno
 (print (reduce #'+ foo))
 (/ 21450611.0 23824968.0)) 

(defun physics (control-state)
  ;;e to escape mouse
  (setf *xpos-old* *xpos*
	*ypos-old* *ypos*
	*zpos-old* *zpos*)
  (when (skey-j-p (keyval :E) control-state) (window:toggle-mouse-capture))
  (when (window:mice-locked-p)
    (when (skey-j-p (keyval :v) control-state) (toggle noclip))
    (when (skey-j-p (keyval :g) control-state) (toggle gravity))
    (when (skey-j-p (keyval :t) control-state) (update-world-vao))
    (when (skey-j-p (keyval :f) control-state) (toggle fly))
    (when (skey-j-p (keyval :c) control-state) (toggle walkblock))
    (when walkblock (
		     what345
		     (truncate *xpos*)
		     (- (truncate *ypos*) 2)
		     (- (truncate *zpos*) 1)
		     *hotbar-selection*))
    (when (skey-j-p (keyval :h) control-state) (time (let ((ans (gl:read-pixels 0 0 1000 1000 :rgba :unsigned-byte)))
				(Setf foo ans))))
    (if fly
	(setf air-friction 0.9)
	(setf air-friction 0.98))
    (controls control-state)
    (let ((blockval (+ 0 *hotbar-selection*)))
      (progn
	(when fist?
	  (when (skey-j-p (mouseval :left) control-state)
	    (setblock-with-update fist-side-x
				  fist-side-y
				  fist-side-z
				  0
				  0))
	  (let ((xop (floor fistx))
		(yop (floor fisty))
		(zop (floor fistz)))
	    (case 1
	      (0 (when (skey-j-p (mouseval :right) control-state)
		   (print (list xop yop zop))
		   (princ (world:skygetlight xop yop zop))))
	      (1 (when (skey-j-p (mouseval :right) control-state)
		   (setblock-with-update (floor fistx)
					 (floor fisty)
					 (floor fistz)
					 blockval
					 (aref mc-blocks::lightvalue blockval))))))))))
  (collide-with-world)
  
  (if fly
      (progn
	(setf *xvel* (* *xvel* air-friction))
	(setf *zvel* (* *zvel* air-friction)))
      (cond (onground
	     (setf *xvel* (* *xvel* walking-friction))
	     (setf *zvel* (* *zvel* walking-friction)))
	    (t (setf *xvel* (* *xvel* (prog2 1.0 0.9)))
	       (setf *zvel* (* *zvel* (prog2 1.0 0.9)))
	     )))
  (when (and gravity (not onground))
    (decf *yvel* (prog2 0.0027222224 (* 0.08 (expt tickscale 2)))))
  (setf *yvel* (* *yvel* (or air-friction 0.9900373 0.99692774)))
  (multiple-value-bind (i- i+ j- j+ k- k+) (block-touches *xpos* *ypos* *zpos* player-aabb)
       (cond ((plusp *xvel*) (when i+ (setf *xvel* 0.0))
	      (minusp *xvel*) (when i- (setf *xvel* 0.0))))
       (cond ((plusp *yvel*) (when j+ (setf *yvel* 0.0))
	      (minusp *yvel*) (when j- (setf *yvel* 0.0))))
       (cond ((plusp *zvel*) (when k+ (setf *zvel* 0.0))
	      (minusp *zvel*) (when k- (setf *zvel* 0.0))))
       (setf onground j-))
  (let ((look-vec (camera-vec-forward *camera*)))
    (let ((avx (aref look-vec 0))
	  (avy (aref look-vec 1))
	  (avz (aref look-vec 2)))
      (let ((vx (- (* reach avx)))
	    (vy (- (* reach avy)))
	    (vz (- (* reach avz))))
	(when (and (window:mice-locked-p) (skey-p (keyval :q) control-state))
	  (big-swing-fist vx vy vz))
	(standard-fist vx vy vz)))))


(defun what345 (x y z w)
  (declare (optimize (speed 3) (safety 0))
	   (type fixnum x y z w))
  (dobox ((x0 -0 1)
	  (z0 -0 1))
	 (plain-setblock (+ x x0) y (+ z z0) w 0)))

(defun collide-with-world ()
  (multiple-value-bind (new-x new-y new-z xclamp yclamp zclamp)
      (aabbcc::step-motion #'myafunc
			   *xpos* *ypos* *zpos*
			   *xvel* *yvel* *zvel*)
    (setf *xpos* new-x)
    (setf *ypos* new-y)
    (setf *zpos* new-z)
    (multiple-value-bind (x y z) (aabbcc::clamp-vec
				  *xvel* *yvel* *zvel*
				  xclamp yclamp zclamp)
      (setf *xvel* x)
      (setf *yvel* y)
      (setf *zvel* z))))

(defparameter *fist-function* (constantly nil))

(defun big-swing-fist (vx vy vz)
  (let ((u 3))
    (aabb-collect-blocks (+ *xpos* -0.0) (+ *ypos* 0.0) (+ *zpos* -0.0) (* u vx) (* u vy) (* u vz)
			 fist-aabb
			 
			 (lambda (x y z)
			   (when (and (<= 0 x 127)
				      (<= 0 y 127)
				      (<= -128 z -1))
			     (let ((blockid 0))
			       (setblock-with-update x y z blockid  (aref mc-blocks::lightvalue blockid))))))))

(defun standard-fist (vx vy vz)
  (multiple-value-bind (frac type blockx blocky blockz)
       (punch-func (+ *xpos* -0.0) (+ *ypos* 0.0) (+ *zpos* -0.0) vx vy vz)
       (if frac
	   (setf fist? t
		 fist-side type
		 fist-side-x blockx
		 fist-side-y blocky
		 fist-side-z blockz
		 fistx (+ *xpos* (* frac vx))
		 fisty (+ *ypos* (* frac vy))
		 fistz (+ *zpos* (* frac vz)))
	   (setf fist? nil))))

(defun punch-func (px py pz vx vy vz)
  (let ((tot-min 2)
	(type :nothing)
	(ansx nil)
	(ansy nil)
	(ansz nil))
     (aabb-collect-blocks px py pz vx vy vz fist-aabb
			  (lambda (x y z)
			    (unless (zerop (world:getblock x y z))
			      (multiple-value-bind (minimum contact-type)
				  (aabbcc::aabb-collide
				   fist-aabb
				   px py pz
				   block-aabb
				   x y z
				   vx vy vz)
				(when (< minimum tot-min)
				  (setq tot-min minimum
					type contact-type
					ansx x
					ansy y
					ansz z))))))
     (values (if (= 2 tot-min) nil tot-min) type ansx ansy ansz)))

(defun myafunc (px py pz vx vy vz)
  (if noclip
      (values 1 nil nil nil)
      (blocktocontact player-aabb px py pz vx vy vz)))

(defmacro with-collidable-blocks ((xvar yvar zvar) (px py pz aabb vx vy vz) &body body)
  `(multiple-value-bind (minx miny minz maxx maxy maxz)
       (get-blocks-around ,px ,py ,pz ,aabb ,vx ,vy ,vz)
     (dobox ((,xvar minx maxx)
	     (,yvar miny maxy)
	     (,zvar minz maxz))
	    ,@body)))

(defmacro null! (&rest args)
  (let (acc)
    (dolist (arg args)
      (push `(setf ,arg nil) acc))
    `(progn ,@acc)))

(defun blocktocontact (aabb px py pz vx vy vz)
  (let ((tot-min 1))
    (let (xyz? xy? xz? yz? x? y? z?)
      (with-collidable-blocks (x y z) (px py pz aabb vx vy vz)
	(when (aref mc-blocks::iscollidable (world:getblock x y z))
	  (multiple-value-bind (minimum type)
	      (aabbcc::aabb-collide
	       aabb
	       px py pz
	       block-aabb
	       x
	       y
	       z
	       vx vy vz)
	    (unless (> minimum tot-min)
	      (when (< minimum tot-min)
		(setq tot-min minimum)
		(null! xyz? xy? yz? xz? x? y? z?))
	      (case type
		(:xyz (setf xyz? t))
		(:xy (setf xy? t))
		(:xz (setf xz? t))
		(:yz (setf yz? t))
		(:x (setf x? t))
		(:y (setf y? t))
		(:z (setf z? t)))))))
      (multiple-value-bind (xclamp yclamp zclamp)
	  (aabbcc::type-collapser vx vy vz xyz? xy? xz? yz? x? y? z?)
	(values
	 tot-min
	 xclamp yclamp zclamp)))))

(defun block-touches (px py pz aabb)
  (let (x- x+ y- y+ z- z+)
    (multiple-value-bind (minx miny minz maxx maxy maxz) (get-blocks-around px py pz player-aabb 0 0 0)
       (dobox ((x minx maxx)
	      (y miny maxy)
	      (z minz maxz))
	     (when (aref mc-blocks::iscollidable (world:getblock x y z))
	       (multiple-value-bind (i+ i- j+ j- k+ k-)
		   (aabbcc::aabb-contact px py pz aabb x y z block-aabb)
		 (if i+ (setq x+ t))
		 (if i- (setq x- t))
		 (if j+ (setq y+ t))
		 (if j- (setq y- t))
		 (if k+ (setq z+ t))
		 (if k- (setq z- t))))))
    (values x- x+ y- y+ z- z+)))

(defun get-blocks-around (px py pz aabb vx vy vz)
  (declare (ignorable aabb vx vy vz))
  (let ((minx (- (truncate px) 2))
	(miny (- (truncate py) 2))
	(minz (- (truncate pz) 2)))
    (let ((maxx (+ minx 5))
	  (maxy (+ miny 4))
	  (maxz (+ minz 5)))
      (values minx miny minz maxx maxy maxz))))

(defun smallest (i j k)
  (if (< i j)
      (if (< i k) ;;i < j j is out
	  (values i t nil nil)	  ;;; i < k and i < j
	  (if (= i k)
	      (values i t nil t) ;;;tied for smallest
	      (values k nil nil t)	     ;;; k < i <j
	      ))
      (if (< j k) ;;i>=j
	  (if (= i j)
	      (values i t t nil)
	      (values j nil t nil)) ;;j<k and i<=j k is nout
	  (if (= i k)
	      (values i t t t)
	      (if (= k j)
		  (values k nil t t)
		  (values k nil nil t))) ;;i>=j>=k 
	  )))

(defun aux-func (x dx)
  (if (zerop dx)
      nil
      (if (plusp dx)
	  (floor (1+ x))
	  (ceiling (1- x)))))


(defun aabb-collect-blocks (px py pz dx dy dz aabb func)
  (declare (ignorable aabb))
  (with-slots ((minx aabbcc::minx) (miny aabbcc::miny) (minz aabbcc::minz)
	       (maxx aabbcc::maxx) (maxy aabbcc::maxy) (maxz aabbcc::maxz)) aabb
    (let ((total 1))
      (let ((pluspdx (plusp dx))
	    (pluspdy (plusp dy))
	    (pluspdz (plusp dz))
	    (zeropdx (zerop dx))
	    (zeropdy (zerop dy))
	    (zeropdz (zerop dz)))
	(declare (ignorable pluspdx pluspdy pluspdz zeropdx zeropdy zeropdz))
	(let ((xoffset (if zeropdx 0 (if pluspdx maxx minx)))
	      (yoffset (if zeropdy 0 (if pluspdy maxy miny)))
	      (zoffset (if zeropdz 0 (if pluspdz maxz minz))))
	  (let ((x (+ px xoffset))
		(y (+ py yoffset))
		(z (+ pz zoffset)))
	    (tagbody
	     rep
	       (let ((i-next (aux-func x dx))
		     (j-next (aux-func y dy))
		     (k-next (aux-func z dz)))
		 (multiple-value-bind (ratio i? j? k?) (smallest (if i-next
						     (/ (- i-next x) dx)
						     most-positive-single-float)
						 (if j-next
						     (/ (- j-next y) dy)
						     most-positive-single-float)
						 (if k-next
						     (/ (- k-next z) dz)
						     most-positive-single-float))	 
		      (let ((newx (if i? i-next (+ x (* dx ratio))))
			    (newy (if j? j-next (+ y (* dy ratio))))
			    (newz (if k? k-next (+ z (* dz ratio)))))
			(let ((aabb-posx (- newx xoffset))
			      (aabb-posy (- newy yoffset))
			      (aabb-posz (- newz zoffset)))
			  (when i?
			    (dobox ((j (floor (+ aabb-posy miny))
				       (ceiling (+ aabb-posy maxy)))
				    (k (floor (+ aabb-posz minz))
				       (ceiling (+ aabb-posz maxz))))
				   (funcall func (if pluspdx newx (1- newx)) j k)))
			  (when j?
			    (dobox ((i (floor (+ aabb-posx minx))
				       (ceiling (+ aabb-posx maxx)))
				    (k (floor (+ aabb-posz minz))
				       (ceiling (+ aabb-posz maxz))))
				   (funcall func i (if pluspdy newy (1- newy)) k)))
			  (when k?
			    (dobox ((j (floor (+ aabb-posy miny))
				       (ceiling (+ aabb-posy maxy)))
				    (i (floor (+ aabb-posx minx))
				       (ceiling (+ aabb-posx maxx))))
				   (funcall func i j (if pluspdz newz (1- newz))))))
			(setf x newx y newy z newz))
		      (decf total ratio)
		      (when (minusp total) (go end))
		      (go rep)))
	     end)))))))

(defun player-pos ()
  (world:chunkhashfunc (truncate *xpos*) (truncate *zpos*) (truncate *ypos*)))

#+nil
(progno
   (hotbar-add e:*scroll-y*)
   (unless (zerop e:*scroll-y*)
     (lcalllist-invalidate :hotbar-selector))
   (progno
    (macrolet ((k (number-key)
		 (let ((symb (intern (write-to-string number-key) :keyword)))
		   `(when (skey-j-p ,symb)
		      (setf *hotbar-selection* ,(1- number-key))
		      (lcalllist-invalidate :hotbar-selector)))))
      (k 1)
      (k 2)
      (k 3)
      (k 4)
      (k 5)
      (k 6)
      (k 7)
      (k 8)
      (k 9))))
