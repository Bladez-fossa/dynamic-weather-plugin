// MIT License

// Copyright (c) Creative Tech Guy 

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

(function() {
	window.addEventListener("load", function() {
		var elems = document.getElementsByClassName("reveal");
		for (var i = 0; i < elems.length; i++) {
			init(elems[i]);
		}
	});

	document.addEventListener("touchmove", drag, {
		passive: false
	});
	document.addEventListener("mousemove", drag);
	document.addEventListener("touchend", stop);
	document.addEventListener("mouseup", stop);

	function drag(evt) {
		if (!window.Reveal.currentDrag) {
			return;
		}
		evt.preventDefault();
		var x = evt.clientX;
		if (evt.touches && evt.touches.length > 0) {
			x = evt.touches[0].clientX;
		}
		window.Reveal.currentDrag.x = x;
		window.Reveal.currentDrag.divider = (Math.max(window.Reveal.currentDrag.rect.left, Math.min(window.Reveal.currentDrag.rect.right, x)) - window.Reveal.currentDrag.rect.left) / window.Reveal.currentDrag.rect.width;
		window.Reveal.currentDrag.update();
	}
	function stop() {
		if (window.Reveal.currentDrag) {
			window.Reveal.currentDrag.update(true);
			window.Reveal.currentDrag = null;
		}
	}

	function init(elem) {
		if (elem.className.indexOf("reveal-loaded") !== -1) {
			return;
		}

		var state = {
			items: [elem.children[0], elem.children[1]],
			divider: 0.5,
			lastX: -1000,
			x: 0,
			rect: elem.getBoundingClientRect(),
			update: update
		};

		var supportsClipPath = true;
		window.requestAnimationFrame(function() {
			if (!state.items[1].style.clipPath) {
				supportsClipPath = false;
				update(true);
			}
		});

		state.items[0].className += " reveal-img";
		state.items[1].className += " reveal-img";

		elem.className += " reveal-loaded";

		var revealBar = createRevealBar();
		update(true);
		revealBar.addEventListener("touchstart", start);
		revealBar.addEventListener("mousedown", start);
		elem.appendChild(revealBar);

		function start() {
			state.dragging = true;
			state.rect = elem.getBoundingClientRect();
			window.Reveal.currentDrag = state;
		}
		function update(force) {
			var percent = state.divider * 100;
			revealBar.style.left = percent + "%";
			if (Math.abs(state.x - state.lastX) < 5 && !force) {
				return;
			}
			if (window.Reveal.onupdate) {
				window.Reveal.onupdate({
					elem: elem,
					percent: percent
				});
			}
			state.lastX = state.x;
			if (!supportsClipPath) {
				state.items[1].style.clip = "rect(0 " + state.rect.width + "px " + state.rect.height + "px " + state.divider * state.rect.width + "px)";
			} else {
				state.items[1].style.clipPath = "inset(0 0 0 " + percent + "%)";
			}
		}
	}

	window.Reveal = {
		currentDrag: null,
		init: init,
		onupdate: null
	};

	function createRevealBar() {
		var revealBar = document.createElement("div");
		revealBar.className = "reveal-bar";

		var revealGrabber = document.createElement("div");
		revealGrabber.className = "reveal-grabber";

		var revealArrows = document.createElement("div");
		revealArrows.className = "reveal-arrows";
		// revealArrows.innerHTML = "◄►";

		var revealArrowLeft = document.createElement('i');
		revealArrowLeft.classList.add('fas', 'fa-angle-left');
		revealArrowLeft.style.marginRight = "0.5rem";
		revealArrows.appendChild(revealArrowLeft);
		var revealArrowRight = document.createElement('i');
		revealArrowRight.classList.add('fas', 'fa-angle-right');
		revealArrows.appendChild(revealArrowRight);

		revealGrabber.appendChild(revealArrows);

		revealBar.appendChild(revealGrabber);
		return revealBar;
	}
})();
