//
//  ContainerViewController.swift
//  TwitterProfile
//
//  Created by OfTheWolf on 08/18/2019.
//  Copyright (c) 2019 OfTheWolf. All rights reserved.
//

import UIKit

public class ContainerViewController : UIViewController, UIScrollViewDelegate {
    private var containerScrollView: UIScrollView! //contains headerVC + bottomVC
    private var overlayScrollView: UIScrollView! //handles whole scroll logic
    private var panViews: [Int: UIView] = [:] {// bottom view(s)/scrollView(s)
        didSet{
            if let scrollView = panViews[currentIndex] as? UIScrollView{
                scrollView.panGestureRecognizer.require(toFail: overlayScrollView.panGestureRecognizer)
                scrollView.donotAdjustContentInset()
                scrollView.addObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize), options: .new, context: nil)
            }
        }
    }

    private var currentIndex: Int = 0
    
    private var pagerTabHeight: CGFloat{
        return bottomVC.pagerTabHeight ?? 44
    }

    private var checkBuffer: CGFloat {
        return 1
    }
    
    weak var dataSource: TPDataSource!
    weak var delegate: TPProgressDelegate?
    
    private var headerView: UIView!{
        return headerVC.view
    }
    
    private var bottomView: UIView!{
        return bottomVC.view
    }
    
    private var headerVC: UIViewController!
    private var bottomVC: (UIViewController & PagerAwareProtocol)!

    private var contentOffsets: [Int: CGFloat] = [:]
    
    
    deinit {
        self.panViews.forEach({ (arg0) in
            let (_, value) = arg0
            if let scrollView = value as? UIScrollView{
                scrollView.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize))
            }
        })
    }
    
    public override func loadView() {
        ///add container scroll view and put headerVC and  bottomPagerVC inside. content size will be superview height + header height.
        containerScrollView = UIScrollView()
        containerScrollView.scrollsToTop = false
        containerScrollView.showsVerticalScrollIndicator = false
        
        ///add overlay scroll view for handling content offsets. content size will be superview height + bottom view contentSize (if UIScrollView) or height (if UIView)
        overlayScrollView = UIScrollView()
        overlayScrollView.showsVerticalScrollIndicator = false
        overlayScrollView.backgroundColor = UIColor.clear

        ///wrap all in a UIView
        let view = UIView()
        view.addSubview(overlayScrollView)
        view.addSubview(containerScrollView)
        self.view = view
        
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        ///Configure overlay scroll
        overlayScrollView.delegate = self
        overlayScrollView.layer.zPosition = CGFloat.greatestFiniteMagnitude
        overlayScrollView.donotAdjustContentInset()
        overlayScrollView.pinEdges(to: self.view)

        ///Configure container scroll
        containerScrollView.addGestureRecognizer(overlayScrollView.panGestureRecognizer)
        containerScrollView.donotAdjustContentInset()
        containerScrollView.pinEdges(to: self.view)
        
        ///Add header view controller
        headerVC = dataSource.headerViewController()
        add(headerVC, to: containerScrollView)
        headerView.constraint(to: containerScrollView, attribute: .leading, secondAttribute: .leading)
        headerView.constraint(to: containerScrollView, attribute: .trailing, secondAttribute: .trailing)
        headerView.constraint(to: containerScrollView, attribute: .top, secondAttribute: .top)
        headerView.constraint(to: containerScrollView, attribute: .width, secondAttribute: .width)
        
        ///Add bottom view controller
        bottomVC = dataSource.bottomViewController()
        bottomVC.pageDelegate = self
        add(bottomVC, to: containerScrollView)
        self.observePanView(bottomVC.currentViewController, at: currentIndex)

        bottomView.constraint(to: containerScrollView, attribute: .leading, secondAttribute: .leading)
        bottomView.constraint(to: containerScrollView, attribute: .trailing, secondAttribute: .trailing)
        bottomView.constraint(to: containerScrollView, attribute: .bottom, secondAttribute: .bottom)
        bottomView.constraint(to: headerView, attribute: .top, secondAttribute: .bottom)
        bottomView.constraint(to: containerScrollView, attribute: .width, secondAttribute: .width)
        bottomView.constraint(to: containerScrollView,
                              attribute: .height,
                              secondAttribute: .height)
        
        ///let know others scroll view configuration is done
        delegate?.tp_scrollViewDidLoad(overlayScrollView)
    }
    
    private func updateOverlayScrollContentSize(with bottomView: UIView){
        self.overlayScrollView.contentSize = getContentSize(for: bottomView)
    }
    
    private func getContentSize(for bottomView: UIView) -> CGSize{
        if let scroll = bottomView as? UIScrollView{
            let bottomHeight = max(scroll.contentSize.height, self.view.frame.height - dataSource.minHeaderHeight() - pagerTabHeight - bottomInset)
            return CGSize(width: scroll.contentSize.width,
                          height: bottomHeight + headerView.frame.height + pagerTabHeight + bottomInset)
        }else{
            let bottomHeight = self.view.frame.height - dataSource.minHeaderHeight() - pagerTabHeight
            return CGSize(width: bottomView.frame.width,
                          height: bottomHeight + headerView.frame.height + pagerTabHeight + bottomInset)
        }
        
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let obj = object as? UIScrollView, keyPath == #keyPath(UIScrollView.contentSize) {
            if let scroll = self.panViews[currentIndex] as? UIScrollView, obj == scroll {
                updateOverlayScrollContentSize(with: scroll)
            }
        }
    }
    
    private var initialContentOffsets: [Int: CGFloat] = [:]
    private func getInitialContentOffsetY(index: Int) -> CGFloat {
        if initialContentOffsets[index] == nil {
            initialContentOffsets[index] = (self.panViews[index] as? UIScrollView)?.contentOffset.y
        }
        return initialContentOffsets[index] ?? 0
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        contentOffsets[currentIndex] = scrollView.contentOffset.y
        let topHeight = bottomView.frame.minY - dataSource.minHeaderHeight()
        
        if (scrollView.contentOffset.y + self.checkBuffer) < topHeight {
            self.containerScrollView.contentOffset.y = scrollView.contentOffset.y
            self.panViews.forEach({ (arg0) in
                let (viewIndex, value) = arg0
                (value as? UIScrollView)?.contentOffset.y = getInitialContentOffsetY(index: viewIndex)
            })
            contentOffsets.removeAll()
        }else{
            self.containerScrollView.contentOffset.y = topHeight
            (self.panViews[currentIndex] as? UIScrollView)?.contentOffset.y = scrollView.contentOffset.y - self.containerScrollView.contentOffset.y + getInitialContentOffsetY(index: currentIndex)
            
        }
        
        let progress = self.containerScrollView.contentOffset.y / topHeight
        self.delegate?.tp_scrollView(self.containerScrollView, didUpdate: progress)
    }
    
    private func observePanView(_ viewController: UIViewController?, at index: Int) {
        guard let newPanView = viewController?.panView() else {
            return
        }
        if let oldPanView = self.panViews[index]  {
            if oldPanView != newPanView {
                if let oldScrollView = oldPanView as? UIScrollView {
                    oldScrollView.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize))
                }
                self.panViews[index] = newPanView
            }
        } else {
            self.panViews[index] = newPanView
        }
    }
}

//MARK: BottomPageDelegate
extension ContainerViewController : BottomPageDelegate {

    public func tp_pageViewController(_ currentViewController: UIViewController?, didSelectPageAt index: Int) {
        currentIndex = index

        if let offset = contentOffsets[index]{
            self.overlayScrollView.contentOffset.y = offset
        }else{
            self.overlayScrollView.contentOffset.y = self.containerScrollView.contentOffset.y
        }
        self.observePanView(currentViewController, at: currentIndex)

        if let panView = self.panViews[currentIndex]{
            updateOverlayScrollContentSize(with: panView)
        }
    }

}
