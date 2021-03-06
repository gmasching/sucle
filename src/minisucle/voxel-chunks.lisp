(defpackage :voxel-chunks
  (:use :cl :utility)
  (:export
   #:getobj
   #:block-coord))
(in-package :voxel-chunks)

;;inner-flat -> array index into array using row-major-aref
;;inner-3d -> some dimension inside 3d array
(deftype block-coord () 'fixnum)
(deftype chunk-data (x y z) `(simple-array * (,(* x y z))))
(deftype inner-flat (x y z) `(integer 0 ,(* x y z)))
(deftype inner-3d (size) `(integer 0 ,size))

(utility:eval-always
  (defun gen-optimized-3d-array (lenx leny lenz name1 name2 name3 name4 name5)
    (let ((foo `(declare (type (inner-3d ,lenx) rx)
			 (type (inner-3d ,leny) ry)
			 (type (inner-3d ,lenz) rz)))
	  (bar `(declare (type (chunk-data ,lenx ,leny ,lenz) data))))
      `(progn
	 (defun ,name3 (&rest rest &key (initial-element *empty-space*))
	   (apply 'make-array
		  ,(* lenx leny lenz)
		  :initial-element initial-element
		  :element-type (downgrade-array:storage-type initial-element)
		  rest))
	 (utility:with-unsafe-speed
	   (declaim (ftype (function ((inner-3d ,lenx) (inner-3d ,leny) (inner-3d ,lenz))
				     (inner-flat ,lenx ,leny ,lenz))
			   ,name1)
		    (inline ,name1)
		    (inline ,name2)
		    (inline ,name4)
		    (inline ,name5))
	   (defun ,name1 (rx ry rz)
	     ,foo
	     ;;FIXME::correct ordering?
	     (+ (* ;;size-z
		 ,lenz
		 (+ (*;;size-y
		     ,leny
		     ry)
		    rz))
		rx))
	   (defun ,name2 (x y z)
	     (declare (type fixnum x y z))
	     (values (mod x ,lenx) (mod y ,leny) (mod z ,lenz)))
	   (defun ,name4 (data rx ry rz)
	     ,foo
	     ,bar
	     (row-major-aref data (,name1 rx ry rz)))
	   (defun (setf ,name4) (value data rx ry rz)
	     ,foo
	     ,bar
	     (setf (row-major-aref data (,name1 rx ry rz))
		   value))
	   (defun ,name5 (&optional (x 0) (y 0) (z 0))
	     (declare (type fixnum x y z))
	     (values (floor x ,lenx) (floor y ,leny) (floor z ,lenz))))))))

;;;;************************************************************************;;;;

(utility:etouq
  (gen-optimized-3d-array 16 16 16 'chunk-ref 'inner 'make-chunk-data 'reference-inside-chunk 'bcoord->ccoord))
;;in order to be correct, the key has to store each value unaltered
;;This is for creating a key for a hash table
;; 'cx' stands for 'chunk-x' etc...
;;smaller names are easier to read and see.
(defun create-chunk-key (&optional (cx 0) (cy 0) (cz 0))
  (list cx cy cz))
(defmacro with-chunk-key-coordinates ((x y z) chunk-key &body body)
  `(destructuring-bind (,x ,y ,z) ,chunk-key
     ,@body))

(defparameter *empty-space* nil)
(defparameter *empty-chunk-data* nil)
;;(defparameter *empty-chunk* nil)
;;the empty-chunk is used as a placeholder when a chunk to reference is required
(defun create-empty-chunk ()
  (create-chunk 0 0 0 :data
		*empty-chunk-data*
		:type :empty))
(defun reset-empty-chunk-value (&optional (empty-space nil))
  (setf *empty-space* empty-space)
  (setf *empty-chunk-data* (downgrade-array:really-downgrade-array
			    (make-chunk-data :initial-element *empty-space*)))
  ;;(setf *empty-chunk* (create-empty-chunk))
  )

(defun empty-chunk-p (chunk)
  (or (null chunk)
      ;;(eq chunk *empty-chunk*)
      (eq (chunk-type chunk) :empty)))
(struct-to-clos:struct->class
 (defstruct chunk
   modified
   ;;last-saved
   type
   x y z
   key
   data
   
   ;;Invalidate a chunk. If used by the main cache to invalidate
   ;;chunks in chunk-array cursors.
   (alive? t)

   (last-read 0)
   (last-modified 0)
   (last-access 0)))

(defun kill-chunk (chunk)
  (setf (chunk-alive? chunk) nil
	(chunk-data chunk) *empty-chunk-data*
	(chunk-type chunk) :dead))

;;FIXME:detect if it actually of type chunk?
(defun valid-chunk-p (chunk)
  (and chunk
       (chunk-alive? chunk)))

;;;;

(defun coerce-empty-chunk-to-regular-chunk (chunk)
  (when (eq (chunk-type chunk) :empty)
    (setf (chunk-data chunk) (make-chunk-data)
	  (chunk-type chunk) :normal)))

;;type can be either :NORMAL or :EMPTY. empty is used to signify that
;;all the chunk data is eql to *empty-space*
;;this is an optimization to save memory
(defun create-chunk (cx cy cz &key (type :normal) data)
  (make-chunk :x cx :y cy :z cz
	      :key (create-chunk-key cx cy cz)
	      :data (ecase type
		      (:normal (or data (make-chunk-data)))
		      (:empty *empty-chunk-data*))
	      :type type))

;;;;************************************************************************;;;;
"
Chunk cache is a hash table. 
(x y z) -> chunk object

When removing or setting chunks, kill the chunk which is no longer to be used."


(defun make-chunk-cache ()
  (make-hash-table :test 'equal))
(defparameter *chunks* (make-chunk-cache))
(defun get-chunk-in-cache (key &optional (cache *chunks*))
  (gethash key cache))
(defun chunk-in-cache-p (key &optional (cache *chunks*))
  (multiple-value-bind (value existsp) (get-chunk-in-cache key cache)
    (declare (ignorable value))
    existsp))

(defun set-chunk-in-cache (key chunk &optional (cache *chunks*))
  (kill-old-chunk key)
  (setf (gethash key cache) chunk))
(defun delete-chunk-in-cache (key &optional (cache *chunks*))
  (when (kill-old-chunk key cache)
    (remhash key cache)))
(defun kill-old-chunk (key &optional (cache *chunks*))
  (multiple-value-bind (old-chunk existp) (gethash key cache)
    (when existp
      (kill-chunk old-chunk)
      (values t))))
(defun total-chunks-in-cache (&optional (cache *chunks*))
  (hash-table-count cache))


;;;;************************************************************************;;;;
;;The cache 
(utility:etouq
  (gen-optimized-3d-array 32 32 32 'cache2_ref 'cache2_inner 'make_cache2 'cache2_reference-inside
			  'cache2_chop ;;Unused
			  ))
(defparameter *cache2* (make_cache2))



;;;;************************************************************************;;;;
;;TODO::optimize 
#+nil
(with-unsafe-speed
  (declaim (inline (setf getobj))
	   (inline getobj)
	   (inline setobj)
	   (inline getchunk)))
(defun (setf getobj) (value x y z)
  (setobj value x y z))
(defun setobj (value x y z ;;space
	       )
  (let ((chunk (multiple-value-call #'getchunk (bcoord->ccoord x y z) t)))
    ;;chunk is not *empty-chunk* because of force-load being passed to obtain-chunk.
    ;;chunk might be a chunk of type :EMPTY with shared data, but since it is being set,
    ;;coerce it to a regular chunk
    ;;FIXME::What does this comment mean here?
    (coerce-empty-chunk-to-regular-chunk chunk)
    (setf (chunk-modified chunk) t)
    
    (multiple-value-bind (rx ry rz) (inner x y z)
      (setf (reference-inside-chunk (chunk-data chunk) rx ry rz) value))))

(defun getobj (x y z ;;space
	       )
  (let ((chunk (multiple-value-call #'getchunk (bcoord->ccoord x y z) nil)))
    (if chunk
	(multiple-value-bind (rx ry rz) (inner x y z)
	  (reference-inside-chunk (chunk-data chunk) rx ry rz))
	*empty-space*)))

(defun getchunk (cx cy cz &optional (allocate-p nil))
  ;;Search cache 1
  (multiple-value-bind (cx2 cy2 cz2) (cache2_inner cx cy cz)
    (let ((maybe-chunk (cache2_reference-inside *cache2* cx2 cy2 cz2)))
      (if maybe-chunk
	  maybe-chunk
	  (let ((main-mem-chunk
		 ;;Search main memory
		 (let ((key (create-chunk-key cx cy cz)))
		   (multiple-value-bind (chunk existp) (get-chunk-in-cache key)
		     (if existp
			 chunk
			 (if allocate-p
			     ;;Create a new chunk if it does not already exist.
			     (let ((new (create-chunk cx cy cz)))
			       (set-chunk-in-cache key new)
			       new)
			     nil))))))
	    (when main-mem-chunk
	      (setf (cache2_reference-inside *cache2* cx2 cy2 cz2) main-mem-chunk))
	    main-mem-chunk)))))

;;;;;
(reset-empty-chunk-value)

(defun test-chunks ()
  
  (let ((acc ()))
    (flet ((add (x y z w)
	     (push (list x y z w) acc)
	     (setf (getobj x y z) w)))

      ;;Not a real test, because blocks can overlap!!!
      #+nil
      (dotimes (i 1000)
	(add (random 10000) (random 10000) (random 10000) (random 10000)))
      (time
       (dotimes (i 10000)
	 (add i i i i)))

      (dolist (item acc)
	(destructuring-bind (x y z w) item
	  (assert (eq w (getobj x y z))))))))

(utility:with-unsafe-speed
  (defun test1 ()
    (time
     (let ((n 2001))
       (dotimes (i (expt 10 6))
	 (setobj n n n n)))))
  (defun test2 ()
    (time
     (dotimes (i (expt 10 6))
       (setobj (random 64) (random 64) (random 64) (random 64)))))

  (defun test3 ()
    (time
     (dotimes (i (expt 10 6))
       (let ((x (mod (* i 7) 512))
	     (y (mod (* i 13) 512))
	     (z (mod (* i 19) 512)))
	 (setobj x y z i))))))
