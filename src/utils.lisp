;;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-
(in-package :squirl)

(declaim (optimize safety debug))

(defun make-adjustable-vector (length)
  (make-array length :adjustable t :fill-pointer 0))

(defun ensure-list (x) (if (listp x) x (list x)))

(defmacro fun (&body body)
  `(lambda (&optional _) (declare (ignorable _)) ,@body))

;; from alexandria:
(declaim (inline delete/swapped-arguments delete-if/swapped-arguments))
(defun delete/swapped-arguments (sequence item &rest keyword-arguments)
  (apply #'delete item sequence keyword-arguments))
(defun delete-if/swapped-arguments (sequence predicate &rest keyword-arguments)
  (apply #'delete-if predicate sequence keyword-arguments))

(define-modify-macro deletef (item &rest remove-keywords)
  delete/swapped-arguments
  "Modify-macro for DELETE. Sets place designated by the first argument to
the result of calling DELETE with ITEM, place, and the REMOVE-KEYWORDS.")

(define-modify-macro delete-iff (predicate &rest remove-keywords)
  delete-if/swapped-arguments
  "Modify-macro for DELETE-IF. Sets place designated by the first argument to
the result of calling DELETE with PREDICATE, place, and the REMOVE-KEYWORDS.")

(defmacro with-gensyms ((&rest vars) &body body)
  `(let ,(loop for var in vars collect `(,var (gensym ,(symbol-name var))))
     ,@body))

(defmacro push-cons (cons place)
  "Like `cl:push', but reuses CONS"
  (with-gensyms (cons-sym)
    `(let ((,cons-sym ,cons))
       (setf (cdr ,cons-sym) ,place
             ,place ,cons-sym))))

(defun expt-mod (b e m &aux (result 1))
  (do ((expt e (ash expt -1))
       (base b (mod (* base base) m)))
      ((zerop expt) result)
    (when (oddp expt)
      (setf result (mod (* result base) m)))))

(defmacro define-constant (name value &optional doc)
  "ANSI-compliant replacement for `defconstant'. cf SBCL Manual 2.3.4."
  `(defconstant ,name (if (boundp ',name) (symbol-value ',name) ,value)
     ,@(when doc (list doc))))

(defun maybe/ (a b)
  (if (zerop b) 0 (/ a b)))

(defmacro with-place (conc-name (&rest slots) form &body body)
  (flet ((conc (a b) (intern (format nil "~A~A" a b))))
    (let ((sm-prefix (if (atom conc-name) conc-name (first conc-name)))
          (acc-prefix (if (atom conc-name) conc-name (second conc-name))))
      `(with-accessors
             ,(mapcar (fun `(,(conc sm-prefix (if (atom _) _ (car _)))
                              ,(conc acc-prefix (if (atom _) _ (cadr _)))))
                      slots)
           ,form
         ,@body))))

;;;
;;; Hashing
;;;

(defun hash-pair (x y &aux (pair (cons x y)))
  (declare (dynamic-extent pair))
  (sxhash pair))
