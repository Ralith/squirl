;;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-
(in-package :squirl)

(declaim (optimize safety debug))

(defstruct (body
             (:constructor
              make-body (%mass %inertia x y 
                               &optional actor &aux
                               (position (if (and (zerop x) (zerop y))
                                             +zero-vector+ (vec x y)))
                               (inverse-mass (/ %mass))
                               (inverse-inertia (/ %inertia)))))
  ;; Actor used for the COLLIDE "callback"
  actor

  shapes ; shapes associated with this body.
  
  ;; Mass properties, and cached inverses
  %mass inverse-mass %inertia inverse-inertia

  ;; Linear components of motion
  (position +zero-vector+ :type vec)
  (velocity +zero-vector+ :type vec)
  (force    +zero-vector+ :type vec)

  ;; Angular components of motion, and cached rotation vector
  (%angle 0) (rotation (load-time-value (vec 1.0 0.0)))
  (angular-velocity 0) (torque 0)

  ;; Velocity bias values used when solving penetrations and correcting constraints.
  (velocity-bias +zero-vector+) (angular-velocity-bias 0))

;;; Wraps the mass, inertia, and angle slots so that setting them updates
;;; the inverse-mass, inverse-inertia, and rotation slots.
(macrolet ((wrap (external internal cached wrapper)
             `(progn (defun ,external (body) (,internal body))
                     (defun (setf ,external) (new-value body)
                       (setf (,internal body) new-value
                             (,cached body) (,wrapper new-value))))))
  (wrap body-mass body-%mass body-inverse-mass /)
  (wrap body-inertia body-%inertia body-inverse-inertia /)
  (wrap body-angle body-%angle body-rotation angle->vec))

(defgeneric body-update-velocity (body gravity damping dt)
  (:method ((body body) gravity damping dt)
    (with-accessors ((angular-velocity body-angular-velocity)
                     (inv-inertia body-inverse-inertia)
                     (velocity body-velocity)
                     (torque body-torque)
                     (force body-force)) body
      (setf velocity
            (vec+ (vec* velocity damping)
                  (vec* (vec+ gravity (vec* force inv-inertia)) dt)))
      (setf angular-velocity
            (+ (* angular-velocity damping)
               (* torque inv-inertia dt))))))

(defgeneric body-update-position (body dt)
  (:method ((body body) dt)
    (with-accessors ((angular-velocity-bias body-angular-velocity-bias)
                     (angular-velocity body-angular-velocity)
                     (velocity-bias body-velocity-bias)
                     (position body-position)
                     (velocity body-velocity)
                     (angle body-angle)) body
      (setf position (vec+ position (vec* (vec+ velocity velocity-bias) dt)))
      (setf angle (+ angle (* angular-velocity angular-velocity-bias dt)))
      (setf velocity-bias +zero-vector+)
      (setf angular-velocity-bias 0))))

(defun body-slew (body pos dt)
  "Modify the velocity of the body so that it will move to the specified absolute coordinates in
the next timestep.
Intended for objects that are moved manually with a custom velocity integration function."
  (setf (body-velocity body)
        (vec* (vec- pos (body-position body))
              (/ dt))))

(defun body-local->world (body vec)
  "Convert body local to world coordinates."
  (vec+ (body-position body)
        (vec-rotate vec (body-rotation body))))

(defun world->body-local (body vec)
  "Convert world to body local coordinates"
  (vec-unrotate (vec- vec (body-position body))
                (body-rotation body)))

(defun body-apply-impulse (body impulse relative)
  "Apply an impulse (in world coordinates) to the body at a point relative to the center of
gravity (also in world coordinates)."
  (with-accessors ((angular-velocity body-angular-velocity)
                   (inverse-inertia body-inverse-inertia)
                   (inverse-mass body-inverse-mass)
                   (velocity body-velocity)) body
    (setf velocity (vec+ velocity (vec* impulse inverse-mass)))
    (incf angular-velocity (* inverse-inertia (vec-cross relative impulse)))))

(defun body-apply-bias-impulse (body impulse relative)
  ;; From C: "Not intended for external use. Used by cpArbiter.c and cpConstraint.c."
  (with-accessors ((angular-velocity-bias body-angular-velocity-bias)
                   (inverse-inertia body-inverse-inertia)
                   (inverse-mass body-inverse-mass)
                   (velocity-bias body-velocity-bias)) body
    (setf velocity-bias (vec+ velocity-bias (vec* impulse inverse-mass)))
    (incf angular-velocity-bias (* inverse-inertia (vec-cross relative impulse)))))

(defun body-reset-forces (body)
  "Zero the forces on a body."
  (setf (body-force body) +zero-vector+
        (body-torque body) 0))

(defun body-apply-force (body force r)
  "Apply a force (in world coordinates) to a body at a point relative to the center
of gravity (also in world coordinates)."
  (setf (body-force body) (vec+ (body-force body) force))
  (incf (body-torque body) (vec-cross r force)))

(defun apply-damped-spring (body1 body2 anchor1 anchor2 rlen k dmp dt)
  "Apply a damped spring force between two bodies.
Warning: Large damping values can be unstable. Use a DAMPED-SPRING constraint for this instead."
  (setf anchor1 (vec-rotate anchor1 (body-rotation body1))
        anchor2 (vec-rotate anchor2 (body-rotation body2)))
  (let* ((delta (vec- (vec+ (body-position body2) anchor2)
                      (vec+ (body-position body1) anchor1)))
         (normal (vec-normalize-safe delta))
         (f-spring (* k (- (vec-length delta) rlen)))
         ;; Calculate the world relative velocities of the anchor points.
         (v1 (vec+ (body-velocity body1)
                   (vec* (vec-perp anchor1) (body-angular-velocity body1))))
         (v2 (vec+ (body-velocity body2)
                   (vec* (vec-perp anchor2) (body-angular-velocity body2))))
         ;; Calculate the damping force.
         ;; This really should be in the impulse solve and can produce problems when
         ;; using large damping values.
         (f-damp (* (vec. (vec- v2 v1) normal)
                    (min dmp (/ (* dt (+ (body-inverse-mass body1)
                                         (body-inverse-mass body2)))))))
         (f (vec* normal (+ f-spring f-damp))))
    ;; Apply!
    (body-apply-force body1 f anchor1)
    (body-apply-force body2 (vec-neg f) anchor2)))
