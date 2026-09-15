// Depthcraft Demo Kit: UI-v0
// Touch-first interactive primitives for non-3D learn-by-doing
// Sandboxed execution environment with no external fetches

// Define a global DepthcraftUIKit namespace
window.DepthcraftUIKit = {
  version: '0.1.0',
  
  // Design tokens for consistent styling
  tokens: {
    colors: {
      primary: '#0891b2',       // cyan-600
      primaryDark: '#0e7490',   // cyan-700
      success: '#059669',       // emerald-600
      error: '#dc2626',         // red-600
      warning: '#d97706',       // amber-600
      background: '#ffffff',
      surface: '#f8fafc',       // slate-50
      border: '#e2e8f0',        // slate-200
      text: '#0f172a',          // slate-900
      textSecondary: '#64748b', // slate-500
      highlight: '#fef3c7',     // amber-100
      disabled: '#cbd5e1'       // slate-300
    },
    spacing: {
      xs: '4px',
      sm: '8px',
      md: '16px',
      lg: '24px',
      xl: '32px'
    },
    borderRadius: {
      sm: '6px',
      md: '12px',
      lg: '16px'
    },
    shadow: {
      sm: '0 1px 2px 0 rgb(0 0 0 / 0.05)',
      md: '0 4px 6px -1px rgb(0 0 0 / 0.1)',
      lg: '0 10px 15px -3px rgb(0 0 0 / 0.1)'
    },
    // 44pt minimum touch target for iPadOS/iOS
    minTouchTarget: '44px',
    fontSize: {
      sm: '14px',
      base: '16px',
      lg: '18px',
      xl: '20px',
      xxl: '24px'
    }
  },

  // Primitive 1: TapReveal
  // Tap to reveal hidden content progressively
  createTapReveal: function(config) {
    const {
      containerId,
      items = [],
      learningGoal = 'Explore concepts by revealing them progressively'
    } = config;

    const container = document.getElementById(containerId);
    if (!container) throw new Error(`Container #${containerId} not found`);

    container.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.md};
      padding: ${this.tokens.spacing.md};
    `;

    let revealedCount = 0;

    items.forEach((item, index) => {
      const card = document.createElement('div');
      card.style.cssText = `
        background: ${this.tokens.colors.surface};
        border: 2px solid ${this.tokens.colors.border};
        border-radius: ${this.tokens.borderRadius.md};
        padding: ${this.tokens.spacing.md};
        transition: all 0.3s ease;
        cursor: pointer;
        min-height: ${this.tokens.minTouchTarget};
        display: flex;
        align-items: center;
      `;

      const content = document.createElement('div');
      content.style.cssText = `
        flex: 1;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      `;

      const title = document.createElement('div');
      title.textContent = item.title || `Item ${index + 1}`;
      title.style.cssText = `
        font-size: ${this.tokens.fontSize.lg};
        font-weight: 600;
        color: ${this.tokens.colors.text};
        margin-bottom: ${this.tokens.spacing.sm};
      `;

      const reveal = document.createElement('div');
      reveal.textContent = item.content || '';
      reveal.style.cssText = `
        font-size: ${this.tokens.fontSize.base};
        color: ${this.tokens.colors.textSecondary};
        max-height: 0;
        overflow: hidden;
        transition: max-height 0.3s ease, opacity 0.3s ease;
        opacity: 0;
        line-height: 1.5;
      `;

      content.appendChild(title);
      content.appendChild(reveal);
      card.appendChild(content);

      let revealed = false;
      card.addEventListener('click', () => {
        if (!revealed) {
          reveal.style.maxHeight = '500px';
          reveal.style.opacity = '1';
          card.style.background = this.tokens.colors.highlight;
          card.style.borderColor = this.tokens.colors.primary;
          revealed = true;
          revealedCount++;
        }
      });

      container.appendChild(card);
    });

    return {
      reset: () => {
        container.innerHTML = '';
        this.createTapReveal(config);
      },
      getProgress: () => ({ revealed: revealedCount, total: items.length })
    };
  },

  // Primitive 2: StepSequence
  // Navigate through sequential steps with controls
  createStepSequence: function(config) {
    const {
      containerId,
      steps = [],
      learningGoal = 'Progress through steps sequentially'
    } = config;

    const container = document.getElementById(containerId);
    if (!container) throw new Error(`Container #${containerId} not found`);

    container.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.md};
      padding: ${this.tokens.spacing.md};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    `;

    let currentStep = 0;

    const progressBar = document.createElement('div');
    progressBar.style.cssText = `
      display: flex;
      gap: ${this.tokens.spacing.xs};
      margin-bottom: ${this.tokens.spacing.md};
    `;

    steps.forEach((_, index) => {
      const dot = document.createElement('div');
      dot.style.cssText = `
        width: 12px;
        height: 12px;
        border-radius: 50%;
        background: ${index === 0 ? this.tokens.colors.primary : this.tokens.colors.disabled};
        transition: background 0.3s ease;
      `;
      dot.dataset.step = index;
      progressBar.appendChild(dot);
    });

    const contentArea = document.createElement('div');
    contentArea.style.cssText = `
      background: ${this.tokens.colors.surface};
      border-radius: ${this.tokens.borderRadius.md};
      padding: ${this.tokens.spacing.lg};
      min-height: 200px;
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.md};
    `;

    const stepTitle = document.createElement('div');
    stepTitle.style.cssText = `
      font-size: ${this.tokens.fontSize.xl};
      font-weight: 600;
      color: ${this.tokens.colors.text};
    `;

    const stepContent = document.createElement('div');
    stepContent.style.cssText = `
      font-size: ${this.tokens.fontSize.base};
      color: ${this.tokens.colors.textSecondary};
      line-height: 1.6;
    `;

    contentArea.appendChild(stepTitle);
    contentArea.appendChild(stepContent);

    const controls = document.createElement('div');
    controls.style.cssText = `
      display: flex;
      gap: ${this.tokens.spacing.md};
      justify-content: space-between;
    `;

    const prevBtn = this.createButton('Previous', 'secondary');
    const nextBtn = this.createButton('Next', 'primary');
    
    controls.appendChild(prevBtn);
    controls.appendChild(nextBtn);

    const updateStep = () => {
      const step = steps[currentStep];
      stepTitle.textContent = step.title || `Step ${currentStep + 1}`;
      stepContent.textContent = step.content || '';

      // Update progress dots
      progressBar.querySelectorAll('div').forEach((dot, index) => {
        dot.style.background = index <= currentStep 
          ? this.tokens.colors.primary 
          : this.tokens.colors.disabled;
      });

      // Update button states
      prevBtn.disabled = currentStep === 0;
      prevBtn.style.opacity = currentStep === 0 ? '0.5' : '1';
      nextBtn.disabled = currentStep === steps.length - 1;
      nextBtn.style.opacity = currentStep === steps.length - 1 ? '0.5' : '1';
    };

    prevBtn.addEventListener('click', () => {
      if (currentStep > 0) {
        currentStep--;
        updateStep();
      }
    });

    nextBtn.addEventListener('click', () => {
      if (currentStep < steps.length - 1) {
        currentStep++;
        updateStep();
      }
    });

    container.appendChild(progressBar);
    container.appendChild(contentArea);
    container.appendChild(controls);

    updateStep();

    return {
      reset: () => {
        currentStep = 0;
        updateStep();
      },
      goToStep: (index) => {
        if (index >= 0 && index < steps.length) {
          currentStep = index;
          updateStep();
        }
      },
      getCurrentStep: () => currentStep
    };
  },

  // Primitive 3: OrderList
  // Drag to reorder items (touch-compatible)
  createOrderList: function(config) {
    const {
      containerId,
      items = [],
      correctOrder = null,
      learningGoal = 'Arrange items in the correct order'
    } = config;

    const container = document.getElementById(containerId);
    if (!container) throw new Error(`Container #${containerId} not found`);

    container.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.sm};
      padding: ${this.tokens.spacing.md};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    `;

    let currentOrder = [...items];
    let draggedElement = null;
    let touchStartY = 0;

    const feedbackDiv = document.createElement('div');
    feedbackDiv.style.cssText = `
      padding: ${this.tokens.spacing.md};
      border-radius: ${this.tokens.borderRadius.md};
      margin-bottom: ${this.tokens.spacing.md};
      font-size: ${this.tokens.fontSize.base};
      display: none;
    `;
    container.appendChild(feedbackDiv);

    const renderList = () => {
      const existingItems = container.querySelectorAll('.order-item');
      existingItems.forEach(item => item.remove());

      currentOrder.forEach((item, index) => {
        const itemDiv = document.createElement('div');
        itemDiv.className = 'order-item';
        itemDiv.dataset.id = item.id || index;
        itemDiv.draggable = true;
        itemDiv.style.cssText = `
          background: ${this.tokens.colors.surface};
          border: 2px solid ${this.tokens.colors.border};
          border-radius: ${this.tokens.borderRadius.md};
          padding: ${this.tokens.spacing.md};
          min-height: ${this.tokens.minTouchTarget};
          display: flex;
          align-items: center;
          gap: ${this.tokens.spacing.md};
          cursor: move;
          touch-action: none;
          user-select: none;
          transition: all 0.2s ease;
        `;

        const handle = document.createElement('div');
        handle.textContent = '☰';
        handle.style.cssText = `
          font-size: ${this.tokens.fontSize.xl};
          color: ${this.tokens.colors.textSecondary};
          cursor: grab;
        `;

        const content = document.createElement('div');
        content.textContent = item.text || item;
        content.style.cssText = `
          flex: 1;
          font-size: ${this.tokens.fontSize.base};
          color: ${this.tokens.colors.text};
        `;

        itemDiv.appendChild(handle);
        itemDiv.appendChild(content);

        // Touch drag handlers
        itemDiv.addEventListener('touchstart', (e) => {
          draggedElement = itemDiv;
          touchStartY = e.touches[0].clientY;
          itemDiv.style.opacity = '0.6';
          itemDiv.style.transform = 'scale(1.02)';
        });

        itemDiv.addEventListener('touchmove', (e) => {
          e.preventDefault();
          if (!draggedElement) return;

          const touch = e.touches[0];
          const currentY = touch.clientY;
          const deltaY = currentY - touchStartY;

          // Find the item we're hovering over
          const items = Array.from(container.querySelectorAll('.order-item'));
          const hoveredItem = items.find(item => {
            if (item === draggedElement) return false;
            const rect = item.getBoundingClientRect();
            return currentY > rect.top && currentY < rect.bottom;
          });

          if (hoveredItem) {
            const draggedIndex = items.indexOf(draggedElement);
            const hoveredIndex = items.indexOf(hoveredItem);
            
            if (draggedIndex < hoveredIndex) {
              hoveredItem.after(draggedElement);
            } else {
              hoveredItem.before(draggedElement);
            }
          }
        });

        itemDiv.addEventListener('touchend', () => {
          if (draggedElement) {
            draggedElement.style.opacity = '1';
            draggedElement.style.transform = 'scale(1)';
            
            // Update current order based on DOM
            const items = Array.from(container.querySelectorAll('.order-item'));
            currentOrder = items.map(item => {
              const id = item.dataset.id;
              return originalItems.find(orig => (orig.id || orig.text) == id);
            });
            
            draggedElement = null;
          }
        });

        // Mouse drag handlers (for desktop testing)
        itemDiv.addEventListener('dragstart', (e) => {
          draggedElement = itemDiv;
          itemDiv.style.opacity = '0.6';
        });

        itemDiv.addEventListener('dragend', () => {
          itemDiv.style.opacity = '1';
          draggedElement = null;
        });

        itemDiv.addEventListener('dragover', (e) => {
          e.preventDefault();
          if (draggedElement && draggedElement !== itemDiv) {
            const bounding = itemDiv.getBoundingClientRect();
            const offset = e.clientY - bounding.top;
            if (offset > bounding.height / 2) {
              itemDiv.after(draggedElement);
            } else {
              itemDiv.before(draggedElement);
            }
          }
        });

        container.appendChild(itemDiv);
      });
    };

    const originalItems = [...items];
    renderList();

    const checkBtn = this.createButton('Check Order', 'primary');
    checkBtn.style.marginTop = this.tokens.spacing.md;
    checkBtn.addEventListener('click', () => {
      if (correctOrder) {
        const isCorrect = currentOrder.every((item, index) => {
          const expectedId = correctOrder[index].id || correctOrder[index];
          const actualId = item.id || item;
          return expectedId === actualId;
        });

        feedbackDiv.style.display = 'block';
        if (isCorrect) {
          feedbackDiv.style.background = this.tokens.colors.success;
          feedbackDiv.style.color = '#ffffff';
          feedbackDiv.textContent = '✓ Correct order!';
        } else {
          feedbackDiv.style.background = this.tokens.colors.warning;
          feedbackDiv.style.color = '#ffffff';
          feedbackDiv.textContent = 'Not quite right. Try again!';
        }
      }
    });
    container.appendChild(checkBtn);

    return {
      reset: () => {
        currentOrder = [...items];
        feedbackDiv.style.display = 'none';
        renderList();
      },
      getCurrentOrder: () => currentOrder
    };
  },

  // Primitive 4: DragMatch
  // Drag items to matching targets
  createDragMatch: function(config) {
    const {
      containerId,
      items = [],
      targets = [],
      matches = {},
      learningGoal = 'Match items to their correct targets'
    } = config;

    const container = document.getElementById(containerId);
    if (!container) throw new Error(`Container #${containerId} not found`);

    container.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.lg};
      padding: ${this.tokens.spacing.md};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    `;

    const itemsArea = document.createElement('div');
    itemsArea.style.cssText = `
      display: flex;
      flex-wrap: wrap;
      gap: ${this.tokens.spacing.md};
      padding: ${this.tokens.spacing.md};
      background: ${this.tokens.colors.surface};
      border-radius: ${this.tokens.borderRadius.md};
      min-height: 100px;
    `;

    const targetsArea = document.createElement('div');
    targetsArea.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.sm};
    `;

    let matchedPairs = {};

    items.forEach(item => {
      const itemDiv = document.createElement('div');
      itemDiv.className = 'drag-item';
      itemDiv.dataset.id = item.id;
      itemDiv.draggable = true;
      itemDiv.style.cssText = `
        background: ${this.tokens.colors.primary};
        color: #ffffff;
        padding: ${this.tokens.spacing.md};
        border-radius: ${this.tokens.borderRadius.md};
        min-width: 120px;
        min-height: ${this.tokens.minTouchTarget};
        display: flex;
        align-items: center;
        justify-content: center;
        cursor: move;
        font-size: ${this.tokens.fontSize.base};
        font-weight: 500;
        touch-action: none;
      `;
      itemDiv.textContent = item.text;

      let draggedElement = null;
      let touchOffset = { x: 0, y: 0 };

      // Touch handlers
      itemDiv.addEventListener('touchstart', (e) => {
        draggedElement = itemDiv;
        const touch = e.touches[0];
        const rect = itemDiv.getBoundingClientRect();
        touchOffset.x = touch.clientX - rect.left;
        touchOffset.y = touch.clientY - rect.top;
        itemDiv.style.opacity = '0.7';
        itemDiv.style.zIndex = '1000';
      });

      itemDiv.addEventListener('touchmove', (e) => {
        e.preventDefault();
        if (!draggedElement) return;

        const touch = e.touches[0];
        draggedElement.style.position = 'fixed';
        draggedElement.style.left = (touch.clientX - touchOffset.x) + 'px';
        draggedElement.style.top = (touch.clientY - touchOffset.y) + 'px';
      });

      itemDiv.addEventListener('touchend', (e) => {
        if (!draggedElement) return;

        const touch = e.changedTouches[0];
        const dropTarget = document.elementFromPoint(touch.clientX, touch.clientY);
        const targetSlot = dropTarget?.closest('.drop-target');

        if (targetSlot) {
          const targetId = targetSlot.dataset.id;
          const itemId = draggedElement.dataset.id;
          
          // Place item in target
          targetSlot.innerHTML = '';
          targetSlot.appendChild(draggedElement);
          matchedPairs[itemId] = targetId;
          
          draggedElement.style.position = 'static';
          draggedElement.style.opacity = '1';
        } else {
          // Return to items area
          itemsArea.appendChild(draggedElement);
          draggedElement.style.position = 'static';
          draggedElement.style.opacity = '1';
        }

        draggedElement.style.zIndex = '1';
        draggedElement = null;
      });

      itemsArea.appendChild(itemDiv);
    });

    targets.forEach(target => {
      const targetDiv = document.createElement('div');
      targetDiv.style.cssText = `
        display: flex;
        gap: ${this.tokens.spacing.md};
        align-items: center;
      `;

      const label = document.createElement('div');
      label.style.cssText = `
        flex: 1;
        font-size: ${this.tokens.fontSize.base};
        color: ${this.tokens.colors.text};
        font-weight: 500;
      `;
      label.textContent = target.text;

      const slot = document.createElement('div');
      slot.className = 'drop-target';
      slot.dataset.id = target.id;
      slot.style.cssText = `
        min-width: 140px;
        min-height: ${this.tokens.minTouchTarget};
        border: 2px dashed ${this.tokens.colors.border};
        border-radius: ${this.tokens.borderRadius.md};
        display: flex;
        align-items: center;
        justify-content: center;
        background: ${this.tokens.colors.surface};
      `;

      targetDiv.appendChild(label);
      targetDiv.appendChild(slot);
      targetsArea.appendChild(targetDiv);
    });

    const feedbackDiv = document.createElement('div');
    feedbackDiv.style.cssText = `
      padding: ${this.tokens.spacing.md};
      border-radius: ${this.tokens.borderRadius.md};
      font-size: ${this.tokens.fontSize.base};
      display: none;
      margin-top: ${this.tokens.spacing.md};
    `;

    const checkBtn = this.createButton('Check Matches', 'primary');
    checkBtn.style.marginTop = this.tokens.spacing.md;
    checkBtn.addEventListener('click', () => {
      let correctCount = 0;
      let totalCount = Object.keys(matches).length;

      Object.entries(matchedPairs).forEach(([itemId, targetId]) => {
        if (matches[itemId] === targetId) {
          correctCount++;
        }
      });

      feedbackDiv.style.display = 'block';
      if (correctCount === totalCount) {
        feedbackDiv.style.background = this.tokens.colors.success;
        feedbackDiv.style.color = '#ffffff';
        feedbackDiv.textContent = '✓ All matches correct!';
      } else {
        feedbackDiv.style.background = this.tokens.colors.warning;
        feedbackDiv.style.color = '#ffffff';
        feedbackDiv.textContent = `${correctCount} out of ${totalCount} correct. Try again!`;
      }
    });

    container.appendChild(itemsArea);
    container.appendChild(targetsArea);
    container.appendChild(checkBtn);
    container.appendChild(feedbackDiv);

    return {
      reset: () => {
        matchedPairs = {};
        feedbackDiv.style.display = 'none';
        itemsArea.innerHTML = '';
        items.forEach(item => {
          const itemDiv = document.createElement('div');
          itemDiv.textContent = item.text;
          itemsArea.appendChild(itemDiv);
        });
      }
    };
  },

  // Primitive 5: HotspotDiagram
  // Tap hotspots on an image or SVG
  createHotspotDiagram: function(config) {
    const {
      containerId,
      imageUrl = null,
      svgContent = null,
      hotspots = [],
      learningGoal = 'Explore diagram by tapping hotspots'
    } = config;

    const container = document.getElementById(containerId);
    if (!container) throw new Error(`Container #${containerId} not found`);

    container.style.cssText = `
      position: relative;
      padding: ${this.tokens.spacing.md};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    `;

    const diagramArea = document.createElement('div');
    diagramArea.style.cssText = `
      position: relative;
      width: 100%;
      max-width: 600px;
      margin: 0 auto;
      border-radius: ${this.tokens.borderRadius.md};
      overflow: hidden;
      background: ${this.tokens.colors.surface};
    `;

    if (svgContent) {
      diagramArea.innerHTML = svgContent;
    } else if (imageUrl) {
      const img = document.createElement('img');
      img.src = imageUrl;
      img.style.cssText = 'width: 100%; display: block;';
      diagramArea.appendChild(img);
    }

    hotspots.forEach(hotspot => {
      const dot = document.createElement('div');
      dot.style.cssText = `
        position: absolute;
        left: ${hotspot.x}%;
        top: ${hotspot.y}%;
        width: ${this.tokens.minTouchTarget};
        height: ${this.tokens.minTouchTarget};
        transform: translate(-50%, -50%);
        background: ${this.tokens.colors.primary};
        border: 3px solid #ffffff;
        border-radius: 50%;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        color: #ffffff;
        font-weight: bold;
        font-size: ${this.tokens.fontSize.base};
        box-shadow: ${this.tokens.shadow.md};
        transition: transform 0.2s ease;
      `;
      dot.textContent = hotspot.label || '?';

      dot.addEventListener('click', () => {
        dot.style.transform = 'translate(-50%, -50%) scale(1.2)';
        setTimeout(() => {
          dot.style.transform = 'translate(-50%, -50%) scale(1)';
        }, 200);

        infoBox.style.display = 'block';
        infoBox.textContent = hotspot.info || 'No information available';
      });

      diagramArea.appendChild(dot);
    });

    const infoBox = document.createElement('div');
    infoBox.style.cssText = `
      margin-top: ${this.tokens.spacing.md};
      padding: ${this.tokens.spacing.md};
      background: ${this.tokens.colors.highlight};
      border-left: 4px solid ${this.tokens.colors.primary};
      border-radius: ${this.tokens.borderRadius.sm};
      font-size: ${this.tokens.fontSize.base};
      color: ${this.tokens.colors.text};
      display: none;
      line-height: 1.5;
    `;
    infoBox.textContent = 'Tap a hotspot to learn more';

    container.appendChild(diagramArea);
    container.appendChild(infoBox);

    return {
      reset: () => {
        infoBox.style.display = 'none';
        infoBox.textContent = 'Tap a hotspot to learn more';
      }
    };
  },

  // Primitive 6: ParamExplorer
  // Sliders/toggles with live visual feedback
  createParamExplorer: function(config) {
    const {
      containerId,
      params = [],
      renderFn = null,
      learningGoal = 'Explore how parameters affect the result'
    } = config;

    const container = document.getElementById(containerId);
    if (!container) throw new Error(`Container #${containerId} not found`);

    container.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.md};
      padding: ${this.tokens.spacing.md};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    `;

    const outputArea = document.createElement('div');
    outputArea.id = `${containerId}-output`;
    outputArea.style.cssText = `
      background: ${this.tokens.colors.surface};
      border-radius: ${this.tokens.borderRadius.md};
      padding: ${this.tokens.spacing.lg};
      min-height: 200px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: ${this.tokens.fontSize.xl};
      color: ${this.tokens.colors.text};
    `;

    const controlsArea = document.createElement('div');
    controlsArea.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.md};
    `;

    let paramValues = {};

    params.forEach(param => {
      paramValues[param.name] = param.default !== undefined ? param.default : 
                                (param.type === 'range' ? param.min : false);

      const controlGroup = document.createElement('div');
      controlGroup.style.cssText = `
        display: flex;
        flex-direction: column;
        gap: ${this.tokens.spacing.sm};
      `;

      const labelRow = document.createElement('div');
      labelRow.style.cssText = `
        display: flex;
        justify-content: space-between;
        align-items: center;
      `;

      const label = document.createElement('label');
      label.textContent = param.label || param.name;
      label.style.cssText = `
        font-size: ${this.tokens.fontSize.base};
        color: ${this.tokens.colors.text};
        font-weight: 500;
      `;

      const valueDisplay = document.createElement('span');
      valueDisplay.style.cssText = `
        font-size: ${this.tokens.fontSize.sm};
        color: ${this.tokens.colors.textSecondary};
        font-family: monospace;
      `;

      labelRow.appendChild(label);
      labelRow.appendChild(valueDisplay);

      if (param.type === 'range') {
        const slider = document.createElement('input');
        slider.type = 'range';
        slider.min = param.min || 0;
        slider.max = param.max || 100;
        slider.step = param.step || 1;
        slider.value = paramValues[param.name];
        slider.style.cssText = `
          width: 100%;
          height: ${this.tokens.minTouchTarget};
          cursor: pointer;
        `;

        valueDisplay.textContent = paramValues[param.name];

        slider.addEventListener('input', (e) => {
          paramValues[param.name] = parseFloat(e.target.value);
          valueDisplay.textContent = paramValues[param.name];
          if (renderFn) renderFn(outputArea, paramValues);
        });

        controlGroup.appendChild(labelRow);
        controlGroup.appendChild(slider);
      } else if (param.type === 'toggle') {
        const toggle = document.createElement('button');
        toggle.style.cssText = `
          width: 60px;
          height: 32px;
          border-radius: 16px;
          border: none;
          cursor: pointer;
          position: relative;
          transition: background 0.3s ease;
          background: ${paramValues[param.name] ? this.tokens.colors.primary : this.tokens.colors.disabled};
        `;

        const knob = document.createElement('div');
        knob.style.cssText = `
          width: 24px;
          height: 24px;
          border-radius: 50%;
          background: white;
          position: absolute;
          top: 4px;
          transition: left 0.3s ease;
          left: ${paramValues[param.name] ? '32px' : '4px'};
        `;
        toggle.appendChild(knob);

        valueDisplay.textContent = paramValues[param.name] ? 'ON' : 'OFF';

        toggle.addEventListener('click', () => {
          paramValues[param.name] = !paramValues[param.name];
          toggle.style.background = paramValues[param.name] ? 
            this.tokens.colors.primary : this.tokens.colors.disabled;
          knob.style.left = paramValues[param.name] ? '32px' : '4px';
          valueDisplay.textContent = paramValues[param.name] ? 'ON' : 'OFF';
          if (renderFn) renderFn(outputArea, paramValues);
        });

        labelRow.appendChild(toggle);
        controlGroup.appendChild(labelRow);
      }

      controlsArea.appendChild(controlGroup);
    });

    container.appendChild(outputArea);
    container.appendChild(controlsArea);

    // Initial render
    if (renderFn) renderFn(outputArea, paramValues);

    return {
      reset: () => {
        params.forEach(param => {
          paramValues[param.name] = param.default !== undefined ? param.default : 
                                    (param.type === 'range' ? param.min : false);
        });
        if (renderFn) renderFn(outputArea, paramValues);
      },
      getValues: () => ({ ...paramValues })
    };
  },

  // Primitive 7: ClassifyBins
  // Sort items into categorical bins
  // Touch-first: tap chip to select, tap bin to place (no HTML5 DnD)
  createClassifyBins: function(config) {
    const {
      containerId,
      items = [],
      bins = [],
      correctBins = {},
      learningGoal = 'Classify items into correct categories'
    } = config;

    const container = document.getElementById(containerId);
    if (!container) throw new Error(`Container #${containerId} not found`);

    container.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.lg};
      padding: ${this.tokens.spacing.md};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    `;

    const itemsPool = document.createElement('div');
    itemsPool.style.cssText = `
      display: flex;
      flex-wrap: wrap;
      gap: ${this.tokens.spacing.sm};
      padding: ${this.tokens.spacing.md};
      background: ${this.tokens.colors.surface};
      border-radius: ${this.tokens.borderRadius.md};
      min-height: 80px;
    `;

    const binsArea = document.createElement('div');
    binsArea.style.cssText = `
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: ${this.tokens.spacing.md};
    `;

    let classifications = {};
    let selectedChip = null;

    // Helper to deselect current chip
    const deselectChip = () => {
      if (selectedChip) {
        selectedChip.style.background = this.tokens.colors.primary;
        selectedChip.style.border = 'none';
        selectedChip.style.transform = 'scale(1)';
        selectedChip = null;
      }
    };

    // Helper to select a chip
    const selectChip = (chip) => {
      deselectChip();
      selectedChip = chip;
      chip.style.background = this.tokens.colors.primaryDark;
      chip.style.border = `3px solid ${this.tokens.colors.warning}`;
      chip.style.transform = 'scale(1.05)';
    };

    items.forEach(item => {
      const chip = document.createElement('div');
      chip.className = 'classify-item';
      chip.dataset.id = item.id || item.text || item.label || item;
      chip.style.cssText = `
        background: ${this.tokens.colors.primary};
        color: #ffffff;
        padding: ${this.tokens.spacing.sm} ${this.tokens.spacing.md};
        border-radius: ${this.tokens.borderRadius.sm};
        font-size: ${this.tokens.fontSize.base};
        cursor: pointer;
        min-height: ${this.tokens.minTouchTarget};
        display: flex;
        align-items: center;
        justify-content: center;
        transition: all 0.2s ease;
        user-select: none;
      `;
      chip.textContent = typeof item === 'string' ? item : (item.text || item.label || item.id || '[No Label]');

      // Tap to select/deselect chip
      chip.addEventListener('click', () => {
        if (selectedChip === chip) {
          // Tap selected chip again to deselect
          deselectChip();
        } else {
          // Select this chip
          selectChip(chip);
        }
      });

      itemsPool.appendChild(chip);
    });

    bins.forEach(bin => {
      const binDiv = document.createElement('div');
      binDiv.style.cssText = `
        border: 2px solid ${this.tokens.colors.border};
        border-radius: ${this.tokens.borderRadius.md};
        padding: ${this.tokens.spacing.md};
        transition: all 0.2s ease;
      `;

      const binLabel = document.createElement('div');
      binLabel.style.cssText = `
        font-size: ${this.tokens.fontSize.lg};
        font-weight: 600;
        color: ${this.tokens.colors.text};
        margin-bottom: ${this.tokens.spacing.sm};
      `;
      binLabel.textContent = bin.label || bin.id;

      const binContent = document.createElement('div');
      binContent.className = 'classify-bin-content';
      binContent.dataset.binId = bin.id;
      binContent.style.cssText = `
        min-height: 60px;
        background: ${this.tokens.colors.surface};
        border-radius: ${this.tokens.borderRadius.sm};
        padding: ${this.tokens.spacing.sm};
        display: flex;
        flex-wrap: wrap;
        gap: ${this.tokens.spacing.xs};
        cursor: pointer;
      `;

      // Tap bin to place selected chip
      const placeBinHandler = () => {
        if (selectedChip) {
          // Move chip to this bin
          binContent.appendChild(selectedChip);
          classifications[selectedChip.dataset.id] = bin.id;
          
          // Reset chip styling (now in bin)
          selectedChip.style.background = this.tokens.colors.primary;
          selectedChip.style.border = 'none';
          selectedChip.style.transform = 'scale(1)';
          
          // Update click handler for chip-in-bin (tap to remove)
          const chipToMove = selectedChip;
          selectedChip = null;
          
          chipToMove.onclick = (e) => {
            e.stopPropagation();
            // Remove from bin back to pool
            itemsPool.appendChild(chipToMove);
            delete classifications[chipToMove.dataset.id];
            
            // Restore original tap behavior
            chipToMove.onclick = function() {
              if (selectedChip === chipToMove) {
                deselectChip();
              } else {
                selectChip(chipToMove);
              }
            };
          };
        }
      };

      binLabel.addEventListener('click', placeBinHandler);
      binContent.addEventListener('click', placeBinHandler);

      binDiv.appendChild(binLabel);
      binDiv.appendChild(binContent);
      binsArea.appendChild(binDiv);
    });

    const controlsRow = document.createElement('div');
    controlsRow.style.cssText = `
      display: flex;
      gap: ${this.tokens.spacing.md};
      align-items: center;
    `;

    const feedbackDiv = document.createElement('div');
    feedbackDiv.style.cssText = `
      padding: ${this.tokens.spacing.md};
      border-radius: ${this.tokens.borderRadius.md};
      font-size: ${this.tokens.fontSize.base};
      display: none;
      flex: 1;
    `;

    const checkBtn = this.createButton('Check Classification', 'primary');
    checkBtn.addEventListener('click', () => {
      let correct = 0;
      let total = Object.keys(correctBins).length;

      Object.entries(classifications).forEach(([itemId, binId]) => {
        if (correctBins[itemId] === binId) {
          correct++;
        }
      });

      feedbackDiv.style.display = 'block';
      if (correct === total && Object.keys(classifications).length === total) {
        feedbackDiv.style.background = this.tokens.colors.success;
        feedbackDiv.style.color = '#ffffff';
        feedbackDiv.textContent = '✓ All items classified correctly!';
      } else {
        feedbackDiv.style.background = this.tokens.colors.warning;
        feedbackDiv.style.color = '#ffffff';
        feedbackDiv.textContent = `${correct} out of ${total} correct. Review and try again!`;
      }
    });

    const clearBtn = this.createButton('Clear Selection', 'secondary');
    clearBtn.addEventListener('click', () => {
      deselectChip();
    });

    controlsRow.appendChild(checkBtn);
    controlsRow.appendChild(clearBtn);

    container.appendChild(itemsPool);
    container.appendChild(binsArea);
    container.appendChild(controlsRow);
    container.appendChild(feedbackDiv);

    return {
      reset: () => {
        deselectChip();
        classifications = {};
        feedbackDiv.style.display = 'none';
        // Move all items back to pool and restore handlers
        const allItems = container.querySelectorAll('.classify-item');
        allItems.forEach(item => {
          itemsPool.appendChild(item);
          item.onclick = function() {
            if (selectedChip === item) {
              deselectChip();
            } else {
              selectChip(item);
            }
          };
        });
      },
      clearSelection: () => {
        deselectChip();
      }
    };
  },

  // Primitive 8: ChallengeLoop
  // Try → feedback → retry pattern (local only)
  createChallengeLoop: function(config) {
    const {
      containerId,
      question = '',
      checkFn = null,
      hintFn = null,
      learningGoal = 'Practice until you get it right'
    } = config;

    const container = document.getElementById(containerId);
    if (!container) throw new Error(`Container #${containerId} not found`);

    container.style.cssText = `
      display: flex;
      flex-direction: column;
      gap: ${this.tokens.spacing.md};
      padding: ${this.tokens.spacing.md};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    `;

    const questionDiv = document.createElement('div');
    questionDiv.style.cssText = `
      font-size: ${this.tokens.fontSize.lg};
      color: ${this.tokens.colors.text};
      font-weight: 500;
      line-height: 1.5;
    `;
    questionDiv.textContent = question;

    const inputArea = document.createElement('textarea');
    inputArea.style.cssText = `
      width: 100%;
      min-height: 100px;
      padding: ${this.tokens.spacing.md};
      border: 2px solid ${this.tokens.colors.border};
      border-radius: ${this.tokens.borderRadius.md};
      font-size: ${this.tokens.fontSize.base};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      resize: vertical;
    `;
    inputArea.placeholder = 'Enter your answer here...';

    const feedbackDiv = document.createElement('div');
    feedbackDiv.style.cssText = `
      padding: ${this.tokens.spacing.md};
      border-radius: ${this.tokens.borderRadius.md};
      font-size: ${this.tokens.fontSize.base};
      display: none;
      line-height: 1.5;
    `;

    const buttonsRow = document.createElement('div');
    buttonsRow.style.cssText = `
      display: flex;
      gap: ${this.tokens.spacing.md};
    `;

    const submitBtn = this.createButton('Submit', 'primary');
    const hintBtn = this.createButton('Hint', 'secondary');
    const resetBtn = this.createButton('Reset', 'secondary');

    let attempts = 0;

    submitBtn.addEventListener('click', () => {
      const answer = inputArea.value.trim();
      attempts++;

      if (checkFn) {
        const result = checkFn(answer);
        feedbackDiv.style.display = 'block';

        if (result.correct) {
          feedbackDiv.style.background = this.tokens.colors.success;
          feedbackDiv.style.color = '#ffffff';
          feedbackDiv.textContent = `✓ Correct! ${result.message || ''} (Attempts: ${attempts})`;
          inputArea.disabled = true;
          submitBtn.disabled = true;
        } else {
          feedbackDiv.style.background = this.tokens.colors.warning;
          feedbackDiv.style.color = '#ffffff';
          feedbackDiv.textContent = `${result.message || 'Not quite right. Try again!'}`;
        }
      }
    });

    hintBtn.addEventListener('click', () => {
      if (hintFn) {
        const hint = hintFn(attempts);
        feedbackDiv.style.display = 'block';
        feedbackDiv.style.background = this.tokens.colors.highlight;
        feedbackDiv.style.color = this.tokens.colors.text;
        feedbackDiv.style.borderLeft = `4px solid ${this.tokens.colors.primary}`;
        feedbackDiv.textContent = `💡 Hint: ${hint}`;
      }
    });

    resetBtn.addEventListener('click', () => {
      inputArea.value = '';
      inputArea.disabled = false;
      submitBtn.disabled = false;
      feedbackDiv.style.display = 'none';
      attempts = 0;
    });

    buttonsRow.appendChild(submitBtn);
    if (hintFn) buttonsRow.appendChild(hintBtn);
    buttonsRow.appendChild(resetBtn);

    container.appendChild(questionDiv);
    container.appendChild(inputArea);
    container.appendChild(buttonsRow);
    container.appendChild(feedbackDiv);

    return {
      reset: () => {
        inputArea.value = '';
        inputArea.disabled = false;
        submitBtn.disabled = false;
        feedbackDiv.style.display = 'none';
        attempts = 0;
      },
      getAttempts: () => attempts
    };
  },

  // Helper: Create styled button
  createButton: function(text, variant = 'primary') {
    const button = document.createElement('button');
    
    const isPrimary = variant === 'primary';
    button.style.cssText = `
      padding: ${this.tokens.spacing.md} ${this.tokens.spacing.lg};
      border: none;
      border-radius: ${this.tokens.borderRadius.md};
      font-size: ${this.tokens.fontSize.base};
      font-weight: 600;
      cursor: pointer;
      min-height: ${this.tokens.minTouchTarget};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      transition: all 0.2s ease;
      background: ${isPrimary ? this.tokens.colors.primary : this.tokens.colors.surface};
      color: ${isPrimary ? '#ffffff' : this.tokens.colors.text};
      border: ${isPrimary ? 'none' : `2px solid ${this.tokens.colors.border}`};
    `;
    button.textContent = text;

    button.addEventListener('mousedown', () => {
      button.style.transform = 'scale(0.98)';
    });

    button.addEventListener('mouseup', () => {
      button.style.transform = 'scale(1)';
    });

    return button;
  },

  // Thin DOM escape: execute custom HTML/JS while respecting constraints
  // Use sparingly - primitives should cover most cases
  injectCustom: function(containerId, htmlContent, jsSetupFn = null) {
    const container = document.getElementById(containerId);
    if (!container) throw new Error(`Container #${containerId} not found`);

    // SECURITY: No network calls allowed
    if (htmlContent.match(/fetch\(|XMLHttpRequest|\.ajax\(|https?:\/\//)) {
      throw new Error('Custom HTML cannot contain network calls or external URLs');
    }

    container.innerHTML = htmlContent;

    if (jsSetupFn && typeof jsSetupFn === 'function') {
      jsSetupFn(container);
    }

    return {
      getContainer: () => container
    };
  }
};

// Auto-initialize marker for Reader
window.DEPTHCRAFT_UI_KIT_LOADED = true;
console.log('✅ Depthcraft UI Kit v0.1.0 loaded');
