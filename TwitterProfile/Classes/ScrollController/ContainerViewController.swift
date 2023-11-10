//
//  ContainerViewController.swift
//  TwitterProfile
//
//  Created by OfTheWolf on 08/18/2019.
//  Copyright (c) 2019 OfTheWolf. All rights reserved.
//

import UIKit

// MARK: - ContainerViewController

public class ContainerViewController: UIViewController, UIScrollViewDelegate {
    private var containerScrollView: UIScrollView! // contains headerVC + bottomVC
    private var overlayScrollView: UIScrollView! // handles whole scroll logic
    private var panViews: [Int: UIView] = [:] { // bottom view(s)/scrollView(s)
        didSet {
            if let scrollView = panViews[currentIndex] as? UIScrollView {
                scrollView.contentInsetAdjustmentBehavior = .never
                scrollView.panGestureRecognizer.require(toFail: overlayScrollView.panGestureRecognizer)
                scrollView.donotAdjustContentInset()
                scrollView.addObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize), options: .new, context: nil)
            }
        }
    }

    private var currentIndex: Int = 0
    
    private var pagerTabHeight: CGFloat {
        return bottomVC.pagerTabHeight ?? 44
    }
    
    private var pagerTabStickyOffset: CGFloat {
        return bottomVC.stickyPagerTab ? 0 : pagerTabHeight
    }

    private var checkBuffer: CGFloat {
        return 1
    }
    
    weak var dataSource: TPDataSource!
    weak var delegate: TPProgressDelegate?
    
    private var headerView: UIView! {
        return headerVC.view
    }
    
    private var bottomView: UIView! {
        return bottomVC.view
    }
    
    private var headerVC: UIViewController!
    private var bottomVC: (UIViewController & PagerAwareProtocol)!

    private var contentOffsets: [Int: CGFloat] = [:]
    
    deinit {
        self.headerView.removeObserver(self, forKeyPath: #keyPath(UIView.bounds))
        self.panViews.forEach { arg0 in
            let (_, value) = arg0
            if let scrollView = value as? UIScrollView {
                scrollView.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize))
            }
        }
    }
    
    override public func loadView() {
        /// add container scroll view and put headerVC and  bottomPagerVC inside. content size will be superview height + header height.
        containerScrollView = UIScrollView()
        containerScrollView.scrollsToTop = false
        containerScrollView.showsVerticalScrollIndicator = false
        containerScrollView.contentInsetAdjustmentBehavior = .never
        
        /// add overlay scroll view for handling content offsets. content size will be superview height + bottom view contentSize (if UIScrollView) or height (if UIView)
        overlayScrollView = UIScrollView()
        overlayScrollView.showsVerticalScrollIndicator = false
        overlayScrollView.backgroundColor = UIColor.clear
        overlayScrollView.contentInsetAdjustmentBehavior = .never

        /// wrap all in a UIView
        let view = UIView()
        view.addSubview(overlayScrollView)
        view.addSubview(containerScrollView)
        self.view = view
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()

        /// Configure overlay scroll
        overlayScrollView.delegate = self
        overlayScrollView.layer.zPosition = CGFloat.greatestFiniteMagnitude
        overlayScrollView.donotAdjustContentInset()
        overlayScrollView.pinEdges(to: view)

        /// Configure container scroll
        containerScrollView.addGestureRecognizer(overlayScrollView.panGestureRecognizer)
        containerScrollView.donotAdjustContentInset()
        containerScrollView.pinEdges(to: view)
        
        /// Add header view controller
        headerVC = dataSource.headerViewController()
        add(headerVC, to: containerScrollView)
        headerView.constraint(to: containerScrollView, attribute: .leading, secondAttribute: .leading)
        headerView.constraint(to: containerScrollView, attribute: .trailing, secondAttribute: .trailing)
        headerView.constraint(to: containerScrollView, attribute: .top, secondAttribute: .top)
        headerView.constraint(to: containerScrollView, attribute: .width, secondAttribute: .width)
        headerView.addObserver(self, forKeyPath: #keyPath(UIView.bounds), options: [.new], context: nil)

        /// Add bottom view controller
        bottomVC = dataSource.bottomViewController()
        bottomVC.pageDelegate = self
        add(bottomVC, to: containerScrollView)
        observePanView(bottomVC.currentViewController, at: currentIndex)

        bottomView.constraint(to: containerScrollView, attribute: .leading, secondAttribute: .leading)
        bottomView.constraint(to: containerScrollView, attribute: .trailing, secondAttribute: .trailing)
        bottomView.constraint(to: containerScrollView, attribute: .bottom, secondAttribute: .bottom)
        bottomView.constraint(to: headerView, attribute: .top, secondAttribute: .bottom)
        bottomView.constraint(to: containerScrollView, attribute: .width, secondAttribute: .width)
        bottomView.constraint(to: containerScrollView,
                              attribute: .height,
                              secondAttribute: .height)
        
        containerScrollView.bringSubviewToFront(headerVC.view)

        /// let know others scroll view configuration is done
        delegate?.tp_scrollViewDidLoad(overlayScrollView)
    }
    
    private var pendingContentSizes: [Int: CGSize] = [:]
    private func updateOverlayScrollContentSize(with bottomView: UIView, pageIndex: Int) {
        let oldContentSize = overlayScrollView.contentSize
        let newContentSize = getContentSize(for: bottomView)
        if newContentSize == oldContentSize {
            return
        }
        let oldY = overlayScrollView.contentOffset.y
        if oldY < 0 {
            pendingContentSizes[pageIndex] = newContentSize
        } else {
            overlayScrollView.contentSize = newContentSize
        }
    }
    
    private func getContentSize(for bottomView: UIView) -> CGSize {
        if let scroll = bottomView as? UIScrollView {
            let bottomHeight = max(scroll.contentSize.height, view.frame.height - dataSource.minHeaderHeight() - pagerTabHeight - bottomInset)
            return CGSize(width: scroll.contentSize.width,
                          height: bottomHeight + headerView.frame.height + pagerTabHeight + bottomInset)
        } else {
            let bottomHeight = view.frame.height - dataSource.minHeaderHeight() - pagerTabHeight
            return CGSize(width: bottomView.frame.width,
                          height: bottomHeight + headerView.frame.height + pagerTabHeight + bottomInset)
        }
    }
    
    private var headerHeight: CGFloat? = nil
    
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if let obj = object as? UIView, obj == headerView, keyPath == #keyPath(UIView.bounds) {
            if !overlayScrollView.isDragging && !overlayScrollView.isDecelerating, headerHeight != headerView.bounds.height {
                headerHeight = headerView.bounds.height
                if let scroll = panViews[currentIndex] as? UIScrollView {
                    updateOverlayScrollContentSize(with: scroll, pageIndex: currentIndex)
                }
            }
        }
        if let obj = object as? UIScrollView, keyPath == #keyPath(UIScrollView.contentSize) {
            if let scroll = panViews[currentIndex] as? UIScrollView, obj == scroll {
                updateOverlayScrollContentSize(with: scroll, pageIndex: currentIndex)
            }
        }
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y > 0 {
            if let size = pendingContentSizes[currentIndex] {
                pendingContentSizes.removeValue(forKey: currentIndex)
                scrollView.contentSize = size
            }
        }
        
        contentOffsets[currentIndex] = scrollView.contentOffset.y
        let topHeight = bottomView.frame.minY - dataSource.minHeaderHeight() + pagerTabStickyOffset
        let scrollViewContentOffsetYDelta = scrollView.contentOffset.y - topHeight

        if scrollViewContentOffsetYDelta < -checkBuffer {
            containerScrollView.contentOffset.y = scrollView.contentOffset.y
            panViews.forEach { arg0 in
                let (viewIndex, value) = arg0
                if let tabScrollView = (value as? UIScrollView) {
                    tabScrollView.contentOffset.y = -tabScrollView.contentInset.top
                }
            }
            contentOffsets.removeAll()
        } else {
            containerScrollView.contentOffset.y = topHeight
            if let tabScrollView = panViews[currentIndex] as? UIScrollView {
                tabScrollView.contentOffset.y = scrollViewContentOffsetYDelta - tabScrollView.contentInset.top
            }
        }
        
        let progress = containerScrollView.contentOffset.y / topHeight
        delegate?.tp_scrollView(
            containerScrollView,
            didUpdate: progress,
            overlayScrollView: overlayScrollView,
            tabScrollView: panViews[currentIndex] as? UIScrollView,
            pageIndex: currentIndex
        )
    }
    
    private func observePanView(_ viewController: UIViewController?, at index: Int) {
        guard let newPanView = viewController?.panView() else {
            return
        }
        if let oldPanView = panViews[index] {
            if oldPanView != newPanView {
                if let oldScrollView = oldPanView as? UIScrollView {
                    oldScrollView.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize))
                }
                panViews[index] = newPanView
            }
        } else {
            panViews[index] = newPanView
        }
    }
}

// MARK: BottomPageDelegate

extension ContainerViewController: BottomPageDelegate {
    public func tp_pageViewController(_ currentViewController: UIViewController?, didSelectPageAt index: Int) {
        currentIndex = index

        if let offset = contentOffsets[index] {
            overlayScrollView.contentOffset.y = offset
        } else {
            overlayScrollView.contentOffset.y = containerScrollView.contentOffset.y
        }
        observePanView(currentViewController, at: currentIndex)

        if let panView = panViews[currentIndex] {
            updateOverlayScrollContentSize(with: panView, pageIndex: currentIndex)
        }
    }
    
    public func tp_pageViewController(_ currentViewController: UIViewController?, didModifyContentOffset offset: CGPoint, pageIndex: Int) {
        if currentIndex == pageIndex {
            observePanView(currentViewController, at: currentIndex)
            
            if let tabScrollView = panViews[currentIndex] as? UIScrollView {
                let topHeight = bottomView.frame.minY - dataSource.minHeaderHeight() + pagerTabStickyOffset

                let scrollY = offset.y // tabScrollView.contentOffset.y
                if scrollY < checkBuffer {
                    overlayScrollView.contentOffset.y = containerScrollView.contentOffset.y
                } else {
                    containerScrollView.contentOffset.y = topHeight
                    overlayScrollView.contentOffset.y = scrollY + topHeight
                }
            }
        } else {
            contentOffsets[pageIndex] = offset.y
        }
    }
}
