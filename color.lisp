;; Copyright (C) 2007 Jonathan Moore Liles
;;
;;  This file is part of stumpwm.
;;
;; stumpwm is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; stumpwm is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this software; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
;; Boston, MA 02111-1307 USA

;; Commentary:
;;
;; This simplified implementation of the the C color code is as follows:
;;
;; ^B bright
;; ^b dim
;; ^n normal (sgr0)
;;
;; ^00 black black
;; ^10 red black
;; ^01 black red
;; ^1* red clear
;;
;; and so on.
;;
;; I won't explain here the many reasons that C is better than ANSI, so just
;; take my word for it.

(in-package :stumpwm)

(export '(*colors* update-color-map))

;; Eight colors. You can redefine these to whatever you like (and
;; then call (update-color-map)).
(defvar *colors*
  '("black"
    "red"
    "green"
    "yellow"
    "blue"
    "magenta"
    "cyan"
    "white"))

(defun adjust-color (color amt)
  (labels ((max-min (x y) (max 0 (min 1 (+ x y)))))
    (setf (xlib:color-red color) (max-min (xlib:color-red color) amt)
	  (xlib:color-green color) (max-min (xlib:color-green color) amt)
	  (xlib:color-blue color) (max-min (xlib:color-blue color) amt))))

;; Normal colors are dimmed and bright colors are intensified in order
;; to more closely resemble the VGA pallet.
(defun update-color-map (screen)
  (let ((cc (screen-message-cc screen))
	(scm (xlib:screen-default-colormap (screen-number screen))))
    (labels ((map-colors (amt)
			 (loop for c in *colors*
			       as color = (xlib:lookup-color scm c)
			       do (adjust-color color amt)
			       collect (xlib:alloc-color scm color))))
      (setf (screen-color-map-normal screen) (apply #'vector (map-colors -0.25))
	    (screen-color-map-bright screen) (apply #'vector (map-colors 0.25))
	    (ccontext-current-map cc) (screen-color-map-normal screen)))))

(defun update-screen-color-context (screen)
  (let* ((scm (xlib:screen-default-colormap (screen-number screen)))
	 (cc (screen-message-cc screen))
	 (bright (xlib:lookup-color scm *text-color*)))
    (setf
      (ccontext-default-fg cc) (screen-fg-color screen)
      (ccontext-default-bg cc) (screen-bg-color screen))
    (adjust-color bright 0.25)
    (setf (ccontext-default-bright cc) (alloc-color screen bright))))

(defun get-bg-color (screen cc color)
  (setf (ccontext-bg cc) color)
  (if color
    (svref (screen-color-map-normal screen) color)
    (ccontext-default-bg cc)))

(defun get-fg-color (screen cc color)
  (setf (ccontext-fg cc) color)
  (if color
    (svref (ccontext-current-map cc) color)
    (if (eq (ccontext-current-map cc) (screen-color-map-bright screen))
      (ccontext-default-bright cc)
      (ccontext-default-fg cc))))

(defun set-color (screen cc s i)
  (let* ((gc (ccontext-gc cc))
	 (l (- (length s) i))
	 (r 2)
	 (f (subseq s i (1+ i)))
	 (b (if (< l 2) "*" (subseq s (1+ i) (+ i 2)))))
    (labels ((update-colors ()
			    (setf
			      (xlib:gcontext-foreground gc) (get-fg-color screen cc (ccontext-fg cc))
			      (xlib:gcontext-background gc) (get-bg-color screen cc (ccontext-bg cc)))))
      (case (elt f 0)
	(#\n ; normal
	 (setf f "*" b "*" r 1
	       (ccontext-current-map cc) (screen-color-map-normal screen))
	 (get-fg-color screen cc nil)
	 (get-bg-color screen cc nil))
	(#\b ; bright off
	 (setf (ccontext-current-map cc) (screen-color-map-normal screen))
	 (update-colors)
	 (return-from set-color 1))
	(#\B ; bright on
	 (setf (ccontext-current-map cc) (screen-color-map-bright screen))
	 (update-colors)
	 (return-from set-color 1))
	(#\^ ; circumflex
	 (return-from set-color 1)))
      (handler-case 
	(let ((fg (if (equal f "*") (progn (get-fg-color screen cc nil) (ccontext-default-fg cc)) (get-fg-color screen cc (parse-integer f))))
	      (bg (if (equal b "*") (progn (get-bg-color screen cc nil) (ccontext-default-bg cc)) (get-bg-color screen cc (parse-integer b)))))
	  (setf (xlib:gcontext-foreground gc) fg
		(xlib:gcontext-background gc) bg))
	(error (c) (dformat 1 "Invalid color code: ~A" c)))) r))

(defun render-strings (screen cc padx pady strings highlights &optional (draw t))
  (let* ((height (+ (xlib:font-descent (screen-font screen))
		    (xlib:font-ascent (screen-font screen))))
	 (width 0)
	 (gc (ccontext-gc cc))
	 (win (ccontext-win cc)))
    (set-color screen cc "n" 0)
    (loop for s in strings
	  ;; We need this so we can track the row for each element
	  for i from 0 to (length strings)
	  do (let ((x 0) (off 0))
	       (loop
		 for st = 0 then (+ en (1+ off))
		 as en = (position #\^ s :start st)
		 do (progn
		      (let ((en (if (and en (eq #\^ (elt s (1+ en)))) (1+ en) en)))
			(when draw
			  (xlib:draw-image-glyphs win gc
						  (+ padx x)
						  (+ pady (* i height)
						     (xlib:font-ascent (screen-font screen)))
						  (subseq s st en)
						  :translate #'translate-id
						  :size 16))
			(setf x (+ x (xlib:text-width (screen-font screen) (subseq s st en) :translate #'translate-id))))
		      (when en
			(setf off (set-color screen cc s (1+ en))))
		      (setf width (max width x)))
		 while en))
	  when (find i highlights :test 'eql)
	  do (when draw (invert-rect screen win
				     0 (* i height)
				     (xlib:drawable-width win)
				     height)))
    width))

