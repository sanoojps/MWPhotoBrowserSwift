//
//  PhotoBrowser.swift
//  Pods
//
//  Created by Tapani Saarinen on 04/09/15.
//
//

import UIKit
import MBProgressHUD
import MediaPlayer
import QuartzCore
import SDWebImage
import MBProgressHUD

class PhotoBrowser: UIViewController, UIScrollViewDelegate, UIActionSheetDelegate {
    private let padding = CGFloat(10.0)

    // Data
    var photoCount = 0
    var photos = [Photo?]()
    var thumbPhotos = [Photo?]()
	var fixedPhotosArray: [Photo]? // Provided via init
	
	// Views
	var pagingScrollView = UIScrollView()
	
	// Paging & layout
	var visiblePages = Set<ZoomingScrollView>()
    var recycledPages = Set<ZoomingScrollView>()
	var currentPageIndex = 0
    var previousPageIndex = 0
    var previousLayoutBounds = CGRectMake(0.0, 0.0, 0.0, 0.0)
	var pageIndexBeforeRotation = 0
	
	// Navigation & controls
	var toolbar = UIToolbar()
	var controlVisibilityTimer: NSTimer?
	var previousButton: UIBarButtonItem?
    var nextButton: UIBarButtonItem?
    var actionButton: UIBarButtonItem?
    var doneButton: UIBarButtonItem?
    
    // Grid
    var gridController: GridViewController?
    var gridPreviousLeftNavItem: UIBarButtonItem?
    var gridPreviousRightNavItem: UIBarButtonItem?
    
    // Appearance
    var previousNavBarHidden = false
    var previousNavBarTranslucent = false
    var previousNavBarStyle = UIBarStyle.Default
    var previousStatusBarStyle = UIStatusBarStyle.Default
    var previousNavBarTintColor: UIColor?
    var previousNavBarBarTintColor: UIColor?
    var previousViewControllerBackButton: UIBarButtonItem?
    var previousNavigationBarBackgroundImageDefault: UIImage?
    var previousNavigationBarBackgroundImageLandscapePhone: UIImage?
    
    // Video
    var currentVideoPlayerViewController: MPMoviePlayerViewController?
    var currentVideoIndex = 0
    var currentVideoLoadingIndicator: UIActivityIndicatorView?
    
    // Misc
    var hasBelongedToViewController = false
    var isVCBasedStatusBarAppearance = false
    var statusBarShouldBeHidden = false
    var displayActionButton = false
    var leaveStatusBarAlone = false
	var performingLayout = false
	var rotating = false
    var viewIsActive = false // active as in it's in the view heirarchy
    var didSavePreviousStateOfNavBar = false
    var skipNextPagingScrollViewPositioning = false
    var viewHasAppearedInitially = false
    var currentGridContentOffset = CGPointMake(0.0, 0.0)
    
    var activityViewController: UIActivityViewController?
    
    weak var delegate: PhotoBrowserDelegate?
    var zoomPhotosToFill = false
    var displayNavArrows = false
    var displaySelectionButtons = false
    var alwaysShowControls = false
    var enableGrid = false
    var enableSwipeToDismiss = false
    var startOnGrid = false
    var autoPlayOnAppear = false
    var delayToHideElements = NSTimeInterval(0.0)

    // Customise image selection icons as they are the only icons with a colour tint
    // Icon should be located in the app's main bundle
    var customImageSelectedIconName = ""
    var customImageSelectedSmallIconName = ""
    
    //MARK: - Init
    
    override init(nibName: String?, bundle nibBundle: NSBundle?) {
        super.init(nibName: nibName, bundle: nibBundle)
        initialisation()
    }
    
    convenience init(delegate: PhotoBrowserDelegate) {
        self.init()
        self.delegate = delegate
        initialisation()
    }

    convenience init(photos: [Photo]) {
        self.init()
        fixedPhotosArray = photos
        initialisation()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        initialisation()
    }

    private func initialisation() {
        // Defaults
        if let vcBasedStatusBarAppearance = NSBundle.mainBundle()
            .objectForInfoDictionaryKey("UIViewControllerBasedStatusBarAppearance") as? Bool
        {
           isVCBasedStatusBarAppearance = vcBasedStatusBarAppearance
        }
        else {
            isVCBasedStatusBarAppearance = true // default
        }
        
        hidesBottomBarWhenPushed = true
        hasBelongedToViewController = false
        photoCount = -1
        previousLayoutBounds = CGRectZero
        currentPageIndex = 0
        previousPageIndex = Int.max
        displayActionButton = true
        displayNavArrows = false
        zoomPhotosToFill = true
        performingLayout = false // Reset on view did appear
        rotating = false
        viewIsActive = false
        enableGrid = true
        startOnGrid = false
        enableSwipeToDismiss = true
        delayToHideElements = 5.0
        currentGridContentOffset = CGPointMake(0, CGFloat.max)
        didSavePreviousStateOfNavBar = false
        self.automaticallyAdjustsScrollViewInsets = false
        
        // Listen for MWPhoto falsetifications
        NSNotificationCenter.defaultCenter().addObserver(
            self,
            selector: Selector("handleMWPhotoLoadingDidEndNotification:"),
            name: MWPHOTO_LOADING_DID_END_NOTIFICATION,
            object: nil)
    }

    deinit {
        clearCurrentVideo()
        pagingScrollView.delegate = nil
        NSNotificationCenter.defaultCenter().removeObserver(self)
        releaseAllUnderlyingPhotos(false)
        SDImageCache.sharedImageCache().clearMemory() // clear memory
    }

    func releaseAllUnderlyingPhotos(preserveCurrent: Bool) {
        // Create a copy in case this array is modified while we are looping through
        // Release photos
        var copy = photos
        for p in copy {
            if let ph = p {
                if let paci = photoAtIndex(currentIndex) {
                    if preserveCurrent && ph.equals(paci) {
                        continue // skip current
                    }
                }
                
                ph.unloadUnderlyingImage()
            }
        }
        
        // Release thumbs
        copy = thumbPhotos
        for p in copy {
            if let ph = p {
                ph.unloadUnderlyingImage()
            }
        }
    }

    override func didReceiveMemoryWarning() {
        // Release any cached data, images, etc that aren't in use.
        releaseAllUnderlyingPhotos(true)
        recycledPages.removeAll(keepCapacity: false)
        
        // Releases the view if it doesn't have a superview.
        super.didReceiveMemoryWarning()
    }

    //MARK: - View Loading

    // Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
    override func viewDidLoad() {
        // Validate grid settings
        if startOnGrid {
            enableGrid = true
        }
        
        //if enableGrid {
        //    enableGrid = [delegate respondsToSelector:Selector("photoBrowser:thumbPhotoAtIndex:)]
        //}
        
        if !enableGrid {
            startOnGrid = false
        }
        
        // View
        view.backgroundColor = UIColor.blackColor()
        view.clipsToBounds = true
        
        // Setup paging scrolling view
        let pagingScrollViewFrame = frameForPagingScrollView
        pagingScrollView = UIScrollView(frame: pagingScrollViewFrame)
        pagingScrollView.autoresizingMask = .FlexibleWidth | .FlexibleHeight
        pagingScrollView.pagingEnabled = true
        pagingScrollView.delegate = self
        pagingScrollView.showsHorizontalScrollIndicator = false
        pagingScrollView.showsVerticalScrollIndicator = false
        pagingScrollView.backgroundColor = UIColor.blackColor()
        pagingScrollView.contentSize = contentSizeForPagingScrollView()
        view.addSubview(pagingScrollView)
        
        // Toolbar
        toolbar = UIToolbar(frame: frameForToolbarAtOrientation(interfaceOrientation))
        toolbar.tintColor = UIColor.whiteColor()
        toolbar.barTintColor = nil
        toolbar.setBackgroundImage(nil, forToolbarPosition: .Any, barMetrics: .Default)
        toolbar.setBackgroundImage(nil, forToolbarPosition: .Any, barMetrics: .Compact)
        toolbar.barStyle = .BlackTranslucent
        toolbar.autoresizingMask = .FlexibleTopMargin | .FlexibleWidth
        
        // Toolbar Items
        if displayNavArrows {
            let arrowPathFormat = "MWPhotoBrowser.bundle/UIBarButtonItemArrow"
            
            let previousButtonImage = UIImage.imageForResourcePath(
                arrowPathFormat + "Left",
                ofType: "png",
                inBundle: NSBundle(forClass: PhotoBrowser.self))
            
            let nextButtonImage = UIImage.imageForResourcePath(
                arrowPathFormat + "Right",
                ofType: "png",
                inBundle: NSBundle(forClass: PhotoBrowser.self))
            
            previousButton = UIBarButtonItem(
                image: previousButtonImage,
                style: UIBarButtonItemStyle.Plain,
                target: self,
                action: Selector("gotoPreviousPage"))
            
            nextButton = UIBarButtonItem(
                image: nextButtonImage,
                style: UIBarButtonItemStyle.Plain,
                target: self,
                action: Selector("gotoNextPage"))
        }
        
        if displayActionButton {
            actionButton = UIBarButtonItem(
                barButtonSystemItem: UIBarButtonSystemItem.Action,
                target: self,
                action: Selector("actionButtonPressed:"))
        }
        
        // Update
        reloadData()
        
        // Swipe to dismiss
        if enableSwipeToDismiss {
            let swipeGesture = UISwipeGestureRecognizer(target: self, action: Selector("doneButtonPressed:"))
            swipeGesture.direction = UISwipeGestureRecognizerDirection.Down | UISwipeGestureRecognizerDirection.Up
            view.addGestureRecognizer(swipeGesture)
        }
        
        // Super
        super.viewDidLoad()
    }

    func performLayout() {
        // Setup
        performingLayout = true
        let photos = numberOfPhotos
        
        // Setup pages
        visiblePages.removeAll()
        recycledPages.removeAll()
        
        // Navigation buttons
        if navigationController!.viewControllers[0] as! NSObject == self {
            // We're first on stack so show done button
            doneButton = UIBarButtonItem(
                title: NSLocalizedString("Done", comment: ""),
                style: UIBarButtonItemStyle.Plain,
                target: self,
                action: Selector("doneButtonPressed:"))
            
            // Set appearance
            if let done = doneButton {
                done.setBackgroundImage(nil, forState: .Normal, barMetrics: .Default)
                done.setBackgroundImage(nil, forState: .Normal, barMetrics: .Compact)
                done.setBackgroundImage(nil, forState: .Highlighted, barMetrics: .Default)
                done.setBackgroundImage(nil, forState: .Highlighted, barMetrics: .Compact)
                done.setTitleTextAttributes([String : AnyObject](), forState: .Normal)
                done.setTitleTextAttributes([String : AnyObject](), forState: .Highlighted)
                
                self.navigationItem.rightBarButtonItem = done
            }
        }
        else {
            // We're not first so show back button
            if let navi = navigationController {
                if let previousViewController = navi.viewControllers[navi.viewControllers.count - 2] as? UINavigationController {
                    let backButtonTitle = previousViewController.navigationItem.backBarButtonItem != nil ?
                        previousViewController.navigationItem.backBarButtonItem!.title :
                        previousViewController.title
                    
                    let newBackButton = UIBarButtonItem(title: backButtonTitle, style: .Plain, target: nil, action: nil)
                    
                    // Appearance
                    newBackButton.setBackButtonBackgroundImage(nil, forState: .Normal, barMetrics: .Default)
                    newBackButton.setBackButtonBackgroundImage(nil, forState: .Normal, barMetrics: .Compact)
                    newBackButton.setBackButtonBackgroundImage(nil, forState: .Highlighted, barMetrics: .Default)
                    newBackButton.setBackButtonBackgroundImage(nil, forState: .Highlighted, barMetrics: .Compact)
                    newBackButton.setTitleTextAttributes([String : AnyObject](), forState: .Normal)
                    newBackButton.setTitleTextAttributes([String : AnyObject](), forState: .Highlighted)
                    
                    previousViewControllerBackButton = previousViewController.navigationItem.backBarButtonItem // remember previous
                    previousViewController.navigationItem.backBarButtonItem = newBackButton
                }
            }
        }

        // Toolbar items
        var hasItems = false
        let fixedSpace = UIBarButtonItem(barButtonSystemItem: .FixedSpace, target: self, action: nil)
        fixedSpace.width = 32.0 // To balance action button
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: self, action: nil)
        var items = [UIBarButtonItem]()

        // Left button - Grid
        if enableGrid {
            hasItems = true
            
            items.append(UIBarButtonItem(
                image: UIImage.imageForResourcePath("MWPhotoBrowser.bundle/UIBarButtonItemGrid",
                    ofType: "png",
                    inBundle: NSBundle(forClass: PhotoBrowser.self)),
                style: .Plain,
                target: self,
                action: Selector("showGridAnimated")))
        }
        else {
            items.append(fixedSpace)
        }

        // Middle - Nav
        if previousButton != nil && nextButton != nil && photos > 1 {
            hasItems = true
            
            items.append(flexSpace)
            items.append(previousButton!)
            items.append(flexSpace)
            items.append(nextButton!)
            items.append(flexSpace)
        }
        else {
            items.append(flexSpace)
        }

        // Right - Action
        if actionButton != nil && !(!hasItems && nil == navigationItem.rightBarButtonItem) {
            items.append(actionButton!)
        }
        else {
            // We're falset showing the toolbar so try and show in top right
            if actionButton != nil {
                navigationItem.rightBarButtonItem = actionButton!
            }
            items.append(fixedSpace)
        }

        // Toolbar visibility
        toolbar.setItems(items, animated: false)
        var hideToolbar = true
        
        for item in items {
            if item != fixedSpace && item != flexSpace {
                hideToolbar = false
                break
            }
        }
        
        if hideToolbar {
            toolbar.removeFromSuperview()
        }
        else {
            view.addSubview(toolbar)
        }
        
        // Update nav
        updateNavigation()
        
        // Content offset
        pagingScrollView.contentOffset = contentOffsetForPageAtIndex(currentPageIndex)
        tilePages()
        performingLayout = false
    }

    var presentingViewControllerPrefersStatusBarHidden: Bool {
        var presenting = presentingViewController
        if let p = presenting as? UINavigationController {
            presenting = p.topViewController
        }
        else {
            // We're in a navigation controller so get previous one!
            if let navi = navigationController {
                if navi.viewControllers.count > 1 {
                    presenting = navi.viewControllers[navi.viewControllers.count - 2] as? UIViewController
                }
            }
        }
        
        if let pres = presenting {
            return pres.prefersStatusBarHidden()
        }
        
        return false
    }

    //MARK: - Appearance

    override func viewWillAppear(animated: Bool) {
        // Super
        super.viewWillAppear(animated)
        
        // Status bar
        if !viewHasAppearedInitially {
            leaveStatusBarAlone = presentingViewControllerPrefersStatusBarHidden
            // Check if status bar is hidden on first appear, and if so then ignore it
            if CGRectEqualToRect(UIApplication.sharedApplication().statusBarFrame, CGRectZero) {
                leaveStatusBarAlone = true
            }
        }
        // Set style
        if !leaveStatusBarAlone && UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.Phone {
            previousStatusBarStyle = UIApplication.sharedApplication().statusBarStyle
            UIApplication.sharedApplication().setStatusBarStyle(UIStatusBarStyle.LightContent, animated: animated)
        }
        
        // Navigation bar appearance
        if let navi = navigationController {
            if !viewIsActive && navi.viewControllers[0] as? PhotoBrowser != self {
                storePreviousNavBarAppearance()
            }
        }
        
        setNavBarAppearance(animated)
        
        // Update UI
        hideControlsAfterDelay()
        
        // Initial appearance
        if !viewHasAppearedInitially {
            if startOnGrid {
                showGrid(false)
            }
        }
        
        // If rotation occured while we're presenting a modal
        // and the index changed, make sure we show the right one falsew
        if currentPageIndex != pageIndexBeforeRotation {
            jumpToPageAtIndex(pageIndexBeforeRotation, animated: false)
        }
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        viewIsActive = true
        
        // Autoplay if first is video
        if !viewHasAppearedInitially {
            if autoPlayOnAppear {
                if let photo = photoAtIndex(currentPageIndex) {
                    if photo.isVideo {
                        playVideoAtIndex(currentPageIndex)
                    }
                }
            }
        }
        
        viewHasAppearedInitially = true
    }

    override func viewWillDisappear(animated: Bool) {
        // Detect if rotation occurs while we're presenting a modal
        pageIndexBeforeRotation = currentPageIndex
        
        if let navi = navigationController {
            let viewControllers = navi.viewControllers as! [UIViewController]
            
            // Check that we're being popped for good
            if viewControllers[0] !== self {
                var selfFound = false
            
                for vc in viewControllers {
                    if vc === self {
                        selfFound = true
                        break;
                    }
                }
                
                if !selfFound {
                    // State
                    viewIsActive = false
                    
                    // Bar state / appearance
                    restorePreviousNavBarAppearance(animated)
                }
            }
            
            // Controls
            navi.navigationBar.layer.removeAllAnimations() // Stop all animations on nav bar
        }
        
        NSObject.cancelPreviousPerformRequestsWithTarget(self) // Cancel any pending toggles from taps
        setControlsHidden(false, animated: false, permanent: true)
        
        // Status bar
        if !leaveStatusBarAlone && UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.Phone {
            UIApplication.sharedApplication().setStatusBarStyle(previousStatusBarStyle, animated: animated)
        }
        
        // Super
        super.viewWillDisappear(animated)
    }

    override func willMoveToParentViewController(parent: UIViewController?) {
        if parent != nil && hasBelongedToViewController {
            fatalError("PhotoBrowser Instance Reuse")
        }
    }

    override func didMoveToParentViewController(parent: UIViewController?) {
        if nil == parent {
            hasBelongedToViewController = true
        }
    }

    //MARK: - Nav Bar Appearance

    func setNavBarAppearance(animated: Bool) {
        if let naviCtl = navigationController {
            naviCtl.setNavigationBarHidden(false, animated: animated)
        
            let navBar = naviCtl.navigationBar
            navBar.tintColor = UIColor.whiteColor()
            navBar.barTintColor = nil
            navBar.shadowImage = nil
            navBar.translucent = true
            navBar.barStyle = .BlackTranslucent
            navBar.setBackgroundImage(nil, forBarMetrics: .Default)
            navBar.setBackgroundImage(nil, forBarMetrics: .Compact)
        }
    }

    func storePreviousNavBarAppearance() {
        didSavePreviousStateOfNavBar = true
        
        if let navi = navigationController {
            previousNavBarBarTintColor = navi.navigationBar.barTintColor
            previousNavBarTranslucent = navi.navigationBar.translucent
            previousNavBarTintColor = navi.navigationBar.tintColor
            previousNavBarHidden = navi.navigationBarHidden
            previousNavBarStyle = navi.navigationBar.barStyle
            previousNavigationBarBackgroundImageDefault = navi.navigationBar.backgroundImageForBarMetrics(.Default)
            previousNavigationBarBackgroundImageLandscapePhone = navi.navigationBar.backgroundImageForBarMetrics(.Compact)
        }
    }

    func restorePreviousNavBarAppearance(animated: Bool) {
        if didSavePreviousStateOfNavBar {
            if let navi = navigationController {
                navi.setNavigationBarHidden(previousNavBarHidden, animated: animated)
                let navBar = navi.navigationBar
                navBar.tintColor = previousNavBarTintColor
                navBar.translucent = previousNavBarTranslucent
                navBar.barTintColor = previousNavBarBarTintColor
                navBar.barStyle = previousNavBarStyle
                navBar.setBackgroundImage(previousNavigationBarBackgroundImageDefault, forBarMetrics: UIBarMetrics.Default)
                navBar.setBackgroundImage(previousNavigationBarBackgroundImageLandscapePhone, forBarMetrics: UIBarMetrics.Compact)

                // Restore back button if we need to
                if previousViewControllerBackButton != nil {
                    let previousViewController = navi.topViewController // We've disappeared so previous is falsew top
                    previousViewController.navigationItem.backBarButtonItem = previousViewControllerBackButton
                    previousViewControllerBackButton = nil
                }
            }
        }
    }

    //MARK: - Layout

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        layoutVisiblePages()
    }

    func layoutVisiblePages() {
        // Flag
        performingLayout = true
        
        // Toolbar
        toolbar.frame = frameForToolbarAtOrientation(self.interfaceOrientation)
        
        // Remember index
        let indexPriorToLayout = currentPageIndex
        
        // Get paging scroll view frame to determine if anything needs changing
        let pagingScrollViewFrame = frameForPagingScrollView
        
        // Frame needs changing
        if !skipNextPagingScrollViewPositioning {
            pagingScrollView.frame = pagingScrollViewFrame
        }
        
        skipNextPagingScrollViewPositioning = false
        
        // Recalculate contentSize based on current orientation
        pagingScrollView.contentSize = contentSizeForPagingScrollView()
        
        // Adjust frames and configuration of each visible page
        for page in visiblePages {
            let index = page.index
            page.frame = frameForPageAtIndex(index)
            
            if let caption = page.captionView {
                caption.frame = frameForCaptionView(caption, index: index)
            }
            
            if let selected = page.selectedButton {
                selected.frame = frameForSelectedButton(selected, atIndex: index)
            }
            
            if let play = page.playButton {
                play.frame = frameForPlayButton(play, atIndex: index)
            }
            
            // Adjust scales if bounds has changed since last time
            if !CGRectEqualToRect(previousLayoutBounds, view.bounds) {
                // Update zooms for new bounds
                page.setMaxMinZoomScalesForCurrentBounds()
                previousLayoutBounds = view.bounds
            }
        }
        
        // Adjust video loading indicator if it's visible
        positionVideoLoadingIndicator()
        
        // Adjust contentOffset to preserve page location based on values collected prior to location
        pagingScrollView.contentOffset = contentOffsetForPageAtIndex(indexPriorToLayout)
        didStartViewingPageAtIndex(currentPageIndex) // initial
        
        // Reset
        currentPageIndex = indexPriorToLayout
        performingLayout = false
        
    }

    //MARK: - Rotation

    override func supportedInterfaceOrientations() -> Int {
        return Int(UIInterfaceOrientationMask.All.rawValue)
    }

    override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        // Remember page index before rotation
        pageIndexBeforeRotation = currentPageIndex
        rotating = true
        
        // In iOS 7 the nav bar gets shown after rotation, but might as well do this for everything!
        if areControlsHidden {
            // Force hidden
            if let navi = navigationController {
                navi.navigationBarHidden = true
            }
        }
    }

    override func willAnimateRotationToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        // Perform layout
        currentPageIndex = pageIndexBeforeRotation
        
        // Delay control holding
        hideControlsAfterDelay()
        
        // Layout
        layoutVisiblePages()
    }

    override func didRotateFromInterfaceOrientation(fromInterfaceOrientation: UIInterfaceOrientation) {
        rotating = false
        // Ensure nav bar isn't re-displayed
        if areControlsHidden {
            if let navi = navigationController {
                navi.navigationBarHidden = false
                navi.navigationBar.alpha = 0
            }
        }
    }

    //MARK: - Data

    var currentIndex: Int {
        return currentPageIndex
    }

    func reloadData() {
        // Reset
        photoCount = -1
        
        // Get data
        let photosNum = numberOfPhotos
        releaseAllUnderlyingPhotos(true)
        photos.removeAll()
        thumbPhotos.removeAll()
        
        for _ in 0...(photosNum - 1) {
            photos.append(nil)
            thumbPhotos.append(nil)
        }

        // Update current page index
        if numberOfPhotos > 0 {
            currentPageIndex = max(0, min(currentPageIndex, photosNum - 1))
        }
        else {
            currentPageIndex = 0
        }
        
        // Update layout
        if isViewLoaded() {
            while pagingScrollView.subviews.count > 0 {
                pagingScrollView.subviews.last!.removeFromSuperview()
            }
            
            performLayout()
            view.setNeedsLayout()
        }
    }

    var numberOfPhotos: Int {
        if photoCount == -1 {
            if let d = delegate {
                photoCount = d.numberOfPhotosInPhotoBrowser(self)
            }
            
            if let fpa = fixedPhotosArray {
                photoCount = fpa.count
            }
        }
        
        if -1 == photoCount {
            photoCount = 0
        }

        return photoCount
    }

    func photoAtIndex(index: Int) -> Photo? {
        var photo: Photo? = nil
        
        if index < photos.count {
            if photos[index] == nil {
                if let d = delegate {
                    photo = d.photoAtIndex(index, photoBrowser: self)
                    
                    if nil == photo && fixedPhotosArray != nil && index < fixedPhotosArray!.count {
                        photo = fixedPhotosArray![index]
                    }
                    
                    if photo != nil {
                        photos[index] = photo
                    }
                }
            }
            else {
                photo = photos[index]
            }
        }
        
        return photo
    }

    func thumbPhotoAtIndex(index: Int) -> Photo? {
        var photo: Photo?
        
        if index < thumbPhotos.count {
            if thumbPhotos[index] == nil {
                if let d = delegate {
                    photo = d.thumbPhotoAtIndex(index, photoBrowser: self)
                
                    if let p = photo {
                        thumbPhotos[index] = p
                    }
                }
            }
            else {
                photo = thumbPhotos[index]
            }
        }
        
        return photo
    }

    func captionViewForPhotoAtIndex(index: Int) -> CaptionView? {
        if let d = delegate {
            var captionView = d.captionViewForPhotoAtIndex(index, photoBrowser: self)
            
            if nil == captionView {
                captionView = CaptionView(photo: photoAtIndex(index))
            }
            
            captionView!.alpha = areControlsHidden ? 0 : 1 // Initial alpha
            return captionView!
        }
        
        return nil
    }

    func photoIsSelectedAtIndex(index: Int) -> Bool {
        var value = false
        if displaySelectionButtons {
            if let d = delegate {
                value = d.isPhotoSelectedAtIndex(index, photoBrowser: self)
            }
        }
        
        return value
    }

    func setPhotoSelected(selected: Bool, atIndex index: Int) {
        if displaySelectionButtons {
            if let d = delegate {
                d.selectedChanged(selected, index: index, photoBrowser: self)
            }
        }
    }

    func imageForPhoto(photo: Photo?) -> UIImage? {
        if let p = photo {
            // Get image or obtain in background
            if let img = p.underlyingImage {
                return img
            }
            else {
                p.loadUnderlyingImageAndNotify()
            }
        }
        
        return nil
    }

    func loadAdjacentPhotosIfNecessary(photo: Photo) {
        let page = pageDisplayingPhoto(photo)
        if let p = page {
            // If page is current page then initiate loading of previous and next pages
            let pageIndex = p.index
            if currentPageIndex == pageIndex {
                if pageIndex > 0 {
                    // Preload index - 1
                    if let photo = photoAtIndex(pageIndex - 1) {
                        if nil == photo.underlyingImage {
                            photo.loadUnderlyingImageAndNotify()
                    
                            //MWLog(@"Pre-loading image at index %lu", (unsigned long)pageIndex-1)
                        }
                    }
                }
                if pageIndex < numberOfPhotos - 1 {
                    // Preload index + 1
                    if let photo = photoAtIndex(pageIndex + 1) {
                        if nil == photo.underlyingImage {
                            photo.loadUnderlyingImageAndNotify()
                    
                            //MWLog(@"Pre-loading image at index %lu", (unsigned long)pageIndex+1)
                        }
                    }
                }
            }
        }
    }

    //MARK: - MWPhoto Loading falsetification

    func handlePhotoLoadingDidEndNotification(notification: NSNotification) {
        if let photo = notification.object as? Photo {
            if let page = pageDisplayingPhoto(photo) {
                if photo.underlyingImage != nil {
                    // Successful load
                    page.displayImage()
                    loadAdjacentPhotosIfNecessary(photo)
                }
                else {
                    // Failed to load
                    page.displayImageFailure()
                }
                // Update nav
                updateNavigation()
            }
        }
    }

    //MARK: - Paging

    func tilePages() {
        // Calculate which pages should be visible
        // Ignore padding as paging bounces encroach on that
        // and lead to false page loads
        let visibleBounds = pagingScrollView.bounds
        var iFirstIndex = Int(floorf(Float((CGRectGetMinX(visibleBounds) + padding * 2.0) / CGRectGetWidth(visibleBounds))))
        var iLastIndex  = Int(floorf(Float((CGRectGetMaxX(visibleBounds) - padding * 2.0 - 1.0) / CGRectGetWidth(visibleBounds))))
        
        if iFirstIndex < 0 {
            iFirstIndex = 0
        }
        
        if iFirstIndex > numberOfPhotos - 1 {
            iFirstIndex = numberOfPhotos - 1
        }
        
        if iLastIndex < 0 {
            iLastIndex = 0
        }
        
        if iLastIndex > numberOfPhotos - 1 {
            iLastIndex = numberOfPhotos - 1
        }
        
        // Recycle false longer needed pages
        var pageIndex = 0
        for page in visiblePages {
            pageIndex = page.index
            
            if pageIndex < iFirstIndex || pageIndex > iLastIndex {
                recycledPages.insert(page)
                
                if let cw = page.captionView {
                    cw.removeFromSuperview()
                }
                
                if let selected = page.selectedButton {
                    selected.removeFromSuperview()
                }
                
                if let play = page.playButton {
                    play.removeFromSuperview()
                }
                
                page.prepareForReuse()
                page.removeFromSuperview()
                
                //MWLog(@"Removed page at index %lu", (unsigned long)pageIndex)
            }
        }
        
        visiblePages.subtract(recycledPages)
        
        while recycledPages.count > 2 { // Only keep 2 recycled pages
            recycledPages.remove(recycledPages.first!)
        }
        
        // Add missing pages
        for index in iFirstIndex...iLastIndex {
            if !isDisplayingPageForIndex(index) {
                // Add new page
                var p = dequeueRecycledPage
                if nil == p {
                    p = ZoomingScrollView(photoBrowser: self)
                }
                
                let page = p!
                
                visiblePages.insert(page)
                configurePage(page, forIndex: index)

                pagingScrollView.addSubview(page)
                // MWLog(@"Added page at index %lu", (unsigned long)index)
                
                // Add caption
                if let captionView = captionViewForPhotoAtIndex(index) {
                    captionView.frame = frameForCaptionView(captionView, index: index)
                    pagingScrollView.addSubview(captionView)
                    page.captionView = captionView
                }
                
                // Add play button if needed
                if page.displayingVideo() {
                    let playButton = UIButton.buttonWithType(.Custom) as! UIButton
                    playButton.setImage(UIImage.imageForResourcePath(
                        "MWPhotoBrowser.bundle/PlayButtonOverlayLarge",
                        ofType: "png",
                        inBundle: NSBundle(forClass: PhotoBrowser.self)), forState: .Normal)
                    
                    playButton.setImage(UIImage.imageForResourcePath(
                        "MWPhotoBrowser.bundle/PlayButtonOverlayLargeTap",
                        ofType: "png",
                        inBundle: NSBundle(forClass: PhotoBrowser.self)), forState: .Highlighted)
                    
                    playButton.addTarget(self, action: Selector("playButtonTapped:"), forControlEvents: .TouchUpInside)
                    playButton.sizeToFit()
                    playButton.frame = frameForPlayButton(playButton, atIndex: index)
                    pagingScrollView.addSubview(playButton)
                    page.playButton = playButton
                }
                
                // Add selected button
                if self.displaySelectionButtons {
                    let selectedButton = UIButton.buttonWithType(.Custom) as! UIButton
                    selectedButton.setImage(UIImage.imageForResourcePath(
                        "MWPhotoBrowser.bundle/ImageSelectedOff",
                        ofType: "png",
                        inBundle: NSBundle(forClass: PhotoBrowser.self)),
                        forState: .Normal)
                    
                    let selectedOnImage: UIImage?
                    if count(customImageSelectedIconName) > 0 {
                        selectedOnImage = UIImage(named: customImageSelectedIconName)
                    }
                    else {
                        selectedOnImage = UIImage.imageForResourcePath(
                            "MWPhotoBrowser.bundle/ImageSelectedOn",
                            ofType: "png",
                            inBundle: NSBundle(forClass: PhotoBrowser.self))
                    }
                    
                    selectedButton.setImage(selectedOnImage, forState: .Selected)
                    selectedButton.sizeToFit()
                    selectedButton.adjustsImageWhenHighlighted = false
                    selectedButton.addTarget(self, action: Selector("selectedButtonTapped:"), forControlEvents: .TouchUpInside)
                    selectedButton.frame = frameForSelectedButton(selectedButton, atIndex: index)
                    pagingScrollView.addSubview(selectedButton)
                    page.selectedButton = selectedButton
                    selectedButton.selected = photoIsSelectedAtIndex(index)
                }
            }
        }
    }

    func updateVisiblePageStates() {
        let copy = visiblePages
        for page in copy {
            // Update selection
            if let selected = page.selectedButton {
                selected.selected = photoIsSelectedAtIndex(page.index)
            }
        }
    }

    func isDisplayingPageForIndex(index: Int) -> Bool {
        for page in visiblePages {
            if page.index == index {
                return true
            }
        }
    
        return false
    }

    func pageDisplayedAtIndex(index: Int) -> ZoomingScrollView? {
        var thePage: ZoomingScrollView?
        for page in visiblePages {
            if page.index == index {
                thePage = page
                break
            }
        }
        return thePage
    }

    func pageDisplayingPhoto(photo: Photo) -> ZoomingScrollView? {
        var thePage: ZoomingScrollView?
        for page in visiblePages {
            if page.photo != nil && page.photo!.equals(photo) {
                thePage = page
                break
            }
        }
        return thePage
    }

    func configurePage(page: ZoomingScrollView, forIndex index: Int) {
        page.frame = frameForPageAtIndex(index)
        page.index = index
        page.photo = photoAtIndex(index)
    }

    var dequeueRecycledPage: ZoomingScrollView? {
        let page = recycledPages.first
        if let p = page {
            recycledPages.remove(p)
        }
        return page
    }

    // Handle page changes
    func didStartViewingPageAtIndex(index: Int) {
        // Handle 0 photos
        if 0 == numberOfPhotos {
            // Show controls
            setControlsHidden(false, animated: true, permanent: true)
            return
        }
        
        // Handle video on page change
        if !rotating || index != currentVideoIndex {
            clearCurrentVideo()
        }
        
        // Release images further away than +/-1
        var i = 0
        if index > 0 {
            // Release anything < index - 1
            for i in 0...(index - 2) {
                if let photo = photos[i] {
                    photo.unloadUnderlyingImage()
                    photos[i] = nil
                    
                    //MWLog(@"Released underlying image at index %lu", (unsigned long)i)
                }
            }
        }
        
        if index < numberOfPhotos - 1 {
            // Release anything > index + 1
            for i in (index + 2)...(photos.count - 1) {
                if let photo = photos[i] {
                    photo.unloadUnderlyingImage()
                    photos[i] = nil
                    
                    //MWLog(@"Released underlying image at index %lu", (unsigned long)i)
                }
            }
        }
        
        // Load adjacent images if needed and the photo is already
        // loaded. Also called after photo has been loaded in background
        let currentPhoto = photoAtIndex(index)
        
        if let cp = currentPhoto {
            if cp.underlyingImage != nil {
                // photo loaded so load ajacent falsew
                loadAdjacentPhotosIfNecessary(cp)
            }
        }
        
        // Notify delegate
        if index != previousPageIndex {
            if let d = delegate {
                d.didDisplayPhotoAtIndex(index, photoBrowser: self)
            }
            previousPageIndex = index
        }
        
        // Update nav
        updateNavigation()
    }

    //MARK: - Frame Calculations

    var frameForPagingScrollView: CGRect {
        var frame = self.view.bounds// UIScreen mainScreen] bounds]
        frame.origin.x -= padding
        frame.size.width += (2.0 * padding)
        return CGRectIntegral(frame)
    }

    func frameForPageAtIndex(index: Int) -> CGRect {
        // We have to use our paging scroll view's bounds, falset frame, to calculate the page placement. When the device is in
        // landscape orientation, the frame will still be in portrait because the pagingScrollView is the root view controller's
        // view, so its frame is in window coordinate space, which is never rotated. Its bounds, however, will be in landscape
        // because it has a rotation transform applied.
        let bounds = pagingScrollView.bounds
        var pageFrame = bounds
        pageFrame.size.width -= (2.0 * padding)
        pageFrame.origin.x = (bounds.size.width * CGFloat(index)) + padding
        return CGRectIntegral(pageFrame)
    }

    func contentSizeForPagingScrollView() -> CGSize {
        // We have to use the paging scroll view's bounds to calculate the contentSize, for the same reason outlined above.
        let bounds = pagingScrollView.bounds
        return CGSizeMake(bounds.size.width * CGFloat(numberOfPhotos), bounds.size.height)
    }

    func contentOffsetForPageAtIndex(index: Int) -> CGPoint {
        let pageWidth = pagingScrollView.bounds.size.width
        let newOffset = CGFloat(index) * pageWidth
        return CGPointMake(newOffset, 0)
    }

    func frameForToolbarAtOrientation(orientation: UIInterfaceOrientation) -> CGRect {
        var height = CGFloat(44.0)
        
        if UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.Phone &&
            UIInterfaceOrientationIsLandscape(orientation)
        {
            height = 32.0
        }
        
        return CGRectIntegral(CGRectMake(0.0, self.view.bounds.size.height - height, self.view.bounds.size.width, height))
    }

    func frameForCaptionView(captionView: CaptionView?, index: Int) -> CGRect {
        if let cw = captionView {
            let pageFrame = frameForPageAtIndex(index)
            let captionSize = cw.sizeThatFits(CGSizeMake(pageFrame.size.width, 0.0))
            let captionFrame = CGRectMake(
                pageFrame.origin.x,
                pageFrame.size.height - captionSize.height - (toolbar.superview != nil ? toolbar.frame.size.height : 0.0),
                pageFrame.size.width,
                captionSize.height)
            
            return CGRectIntegral(captionFrame)
        }
        
        return CGRectZero
    }

    func frameForSelectedButton(selectedButton: UIButton, atIndex index: Int) -> CGRect {
        let pageFrame = frameForPageAtIndex(index)
        let padding = CGFloat(20.0)
        var yOffset = CGFloat(0.0)
        
        if !areControlsHidden {
            let navBar = navigationController!.navigationBar
            yOffset = navBar.frame.origin.y + navBar.frame.size.height
        }
        
        let selectedButtonFrame = CGRectMake(
            pageFrame.origin.x + pageFrame.size.width - selectedButton.frame.size.width - padding,
            padding + yOffset,
            selectedButton.frame.size.width,
            selectedButton.frame.size.height)
        
        return CGRectIntegral(selectedButtonFrame)
    }

    func frameForPlayButton(playButton: UIButton, atIndex index: Int) -> CGRect {
        let pageFrame = frameForPageAtIndex(index)
        return CGRectMake(
            CGFloat(floorf(Float(CGRectGetMidX(pageFrame) - playButton.frame.size.width / 2.0))),
            CGFloat(floorf(Float(CGRectGetMidY(pageFrame) - playButton.frame.size.height / 2.0))),
            playButton.frame.size.width,
            playButton.frame.size.height)
    }

    //MARK: - UIScrollView Delegate

    func scrollViewDidScroll(scrollView: UIScrollView) {
        // Checks
        if !viewIsActive || performingLayout || rotating {
            return
        }
        
        // Tile pages
        tilePages()
        
        // Calculate current page
        let visibleBounds = pagingScrollView.bounds
        var index = Int(floorf(Float(CGRectGetMidX(visibleBounds) / CGRectGetWidth(visibleBounds))))
        if index < 0 {
            index = 0
        }
        
        if index > numberOfPhotos - 1 {
            index = numberOfPhotos - 1
        }
        
        let previousCurrentPage = currentPageIndex
        currentPageIndex = index
        
        if currentPageIndex != previousCurrentPage {
            didStartViewingPageAtIndex(index)
        }
    }

    func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        // Hide controls when dragging begins
        setControlsHidden(true, animated: true, permanent: false)
    }

    func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        // Update nav when page changes
        updateNavigation()
    }

    //MARK: - Navigation

    func updateNavigation() {
        // Title
        let photos = numberOfPhotos
        if let gc = gridController {
            if gc.selectionMode {
                self.title = NSLocalizedString("Select Photos", comment: "")
            }
            else {
                let photosText: String
                
                if 1 == photos {
                    photosText = NSLocalizedString("photo", comment: "Used in the context: '1 photo'")
                }
                else {
                    photosText = NSLocalizedString("photos", comment: "Used in the context: '3 photos'")
                }
                
                title = "\(photos) \(photosText)"
            }
        }
        else
        if photos > 1 {
            if let d = delegate {
                title = d.titleForPhotoAtIndex(currentPageIndex, photoBrowser: self)
            }
            
            if nil == title {
                let str = NSLocalizedString("of", comment: "Used in the context: 'Showing 1 of 3 items'")
                title = "\(currentPageIndex + 1) \(str) \(numberOfPhotos)"
            }
        }
        else {
            title = nil
        }
        
        // Buttons
        if let prev = previousButton {
            prev.enabled = (currentPageIndex > 0)
        }
        
        if let next = nextButton {
            next.enabled = (currentPageIndex < photos - 1)
        }
        
        // Disable action button if there is false image or it's a video
        if let ab = actionButton {
            let photo = photoAtIndex(currentPageIndex)

            if photo != nil && (photo!.underlyingImage == nil || photo!.isVideo) {
                ab.enabled = false
                ab.tintColor = UIColor.clearColor() // Tint to hide button
            }
            else {
                ab.enabled = true
                ab.tintColor = nil
            }
        }
    }

    func jumpToPageAtIndex(index: Int, animated: Bool) {
        // Change page
        if index < numberOfPhotos {
            let pageFrame = frameForPageAtIndex(index)
            pagingScrollView.setContentOffset(CGPointMake(pageFrame.origin.x - padding, 0), animated: animated)
            updateNavigation()
        }
        
        // Update timer to give more time
        hideControlsAfterDelay()
    }

    func gotoPreviousPage() {
        showPreviousPhotoAnimated(false)
    }
    func gotoNextPage() {
        showNextPhotoAnimated(false)
    }

    func showPreviousPhotoAnimated(animated: Bool) {
        jumpToPageAtIndex(currentPageIndex - 1, animated: animated)
    }

    func showNextPhotoAnimated(animated: Bool) {
        jumpToPageAtIndex(currentPageIndex + 1, animated: animated)
    }

    //MARK: - Interactions

    func selectedButtonTapped(sender: AnyObject) {
        let selectedButton = sender as! UIButton
        selectedButton.selected = !selectedButton.selected
    
        var index = Int.max
        for page in visiblePages {
            if page.selectedButton == selectedButton {
                index = page.index
                break
            }
        }
    
        if index != Int.max {
            setPhotoSelected(selectedButton.selected, atIndex: index)
        }
    }

    func playButtonTapped(sender: AnyObject) {
        let playButton = sender as! UIButton
        var index = Int.max
    
        for page in visiblePages {
            if page.playButton == playButton {
                index = page.index
                break
            }
        }
        
        if index != Int.max {
            if nil == currentVideoPlayerViewController {
                playVideoAtIndex(index)
            }
        }
    }

    //MARK: - Video

    func playVideoAtIndex(index: Int) {
        let photo = photoAtIndex(index)
        
        // Valid for playing
        currentVideoIndex = index
        clearCurrentVideo()
        setVideoLoadingIndicatorVisible(true, atPageIndex: index)
        
        // Get video and play
        if let p = photo {
            p.getVideoURL() { url in
                if let u = url {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.playVideo(u, atPhotoIndex: index)
                    }
                }
                else {
                    self.setVideoLoadingIndicatorVisible(false, atPageIndex: index)
                }
            }
        }
    }

    func playVideo(videoURL: NSURL, atPhotoIndex index: Int) {
        // Setup player
        currentVideoPlayerViewController = MPMoviePlayerViewController(contentURL: videoURL)
        
        if let player = currentVideoPlayerViewController {
            player.moviePlayer.prepareToPlay()
            player.moviePlayer.shouldAutoplay = true
            player.moviePlayer.scalingMode = .AspectFit
            player.modalTransitionStyle = .CrossDissolve
        
            // Remove the movie player view controller from the "playback did finish" falsetification observers
            // Observe ourselves so we can get it to use the crossfade transition
            NSNotificationCenter.defaultCenter().removeObserver(
                player,
                name: MPMoviePlayerPlaybackDidFinishNotification,
                object: player.moviePlayer)
        
            NSNotificationCenter.defaultCenter().addObserver(
                self,
                selector: Selector("videoFinishedCallback:"),
                name: MPMoviePlayerPlaybackDidFinishNotification,
                object: player.moviePlayer)

            // Show
            presentViewController(player, animated: true, completion: nil)
        }
    }

    func videoFinishedCallback(notification: NSNotification) {
        if let player = currentVideoPlayerViewController {
            // Remove observer
            NSNotificationCenter.defaultCenter().removeObserver(
                self,
                name: MPMoviePlayerPlaybackDidFinishNotification,
                object: player.moviePlayer)
            
            // Clear up
            clearCurrentVideo()
            
            // Dismiss
            if let errorObj: AnyObject? = notification.userInfo?[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] {
                let error = MPMovieFinishReason(rawValue: errorObj as! Int)
            
                if error == .PlaybackError {
                    // Error occured so dismiss with a delay incase error was immediate and we need to wait to dismiss the VC
                    dispatch_after(
                        dispatch_time(DISPATCH_TIME_NOW, Int64(1.0 * Double(NSEC_PER_SEC))),
                        dispatch_get_main_queue())
                    {
                        self.dismissViewControllerAnimated(true, completion: nil)
                    }
                    
                    return
                }
            }
        }
        
        dismissViewControllerAnimated(true, completion: nil)
    }

    func clearCurrentVideo() {
        if currentVideoPlayerViewController != nil {
            currentVideoLoadingIndicator!.removeFromSuperview()
            currentVideoPlayerViewController = nil
            currentVideoLoadingIndicator = nil
            currentVideoIndex = Int.max
        }
    }

    func setVideoLoadingIndicatorVisible(visible: Bool, atPageIndex: Int) {
        if currentVideoLoadingIndicator != nil && !visible {
            currentVideoLoadingIndicator!.removeFromSuperview()
            currentVideoLoadingIndicator = nil
        }
        else
        if nil == currentVideoLoadingIndicator && visible {
            currentVideoLoadingIndicator = UIActivityIndicatorView(frame: CGRectZero)
            currentVideoLoadingIndicator!.sizeToFit()
            currentVideoLoadingIndicator!.startAnimating()
            pagingScrollView.addSubview(currentVideoLoadingIndicator!)
            
            positionVideoLoadingIndicator()
        }
    }

    func positionVideoLoadingIndicator() {
        if currentVideoLoadingIndicator != nil && currentVideoIndex != Int.max {
            let frame = frameForPageAtIndex(currentVideoIndex)
            currentVideoLoadingIndicator!.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame))
        }
    }

    //MARK: - Grid

    func showGridAnimated() {
        showGrid(true)
    }

    func showGrid(animated: Bool) {
        if gridController != nil {
            return
        }
        
        // Init grid controller
        gridController = GridViewController()
        
        if let gc = gridController {
            gc.initialContentOffset = currentGridContentOffset
            gc.browser = self
            gc.selectionMode = displaySelectionButtons
            gc.view.frame = view.bounds
            
            if let gc = gridController {
                gc.view.frame = CGRectOffset(gc.view.frame, 0, (startOnGrid ? -1 : 1) * view.bounds.size.height)
            }
        
            // Stop specific layout being triggered
            skipNextPagingScrollViewPositioning = true
            
            // Add as a child view controller
            addChildViewController(gc)
            view.addSubview(gc.view)
        
            // Perform any adjustments
            gc.view.layoutIfNeeded()
            gc.adjustOffsetsAsRequired()
        
            // Hide action button on nav bar if it exists
            if navigationItem.rightBarButtonItem == actionButton {
                gridPreviousRightNavItem = actionButton
                navigationItem.setRightBarButtonItem(nil, animated: true)
            }
            else {
                gridPreviousRightNavItem = nil
            }
            
            // Update
            updateNavigation()
            setControlsHidden(false, animated: true, permanent: true)
            
            // Animate grid in and photo scroller out
            gc.willMoveToParentViewController(self)
            UIView.animateWithDuration(
                animated ? 0.3 : 0,
                animations: {
                    gc.view.frame = self.view.bounds
                    let pagingFrame = self.frameForPagingScrollView
                    self.pagingScrollView.frame = CGRectOffset(
                        pagingFrame,
                        0,
                        (self.startOnGrid ? 1 : -1) * pagingFrame.size.height)
                },
                completion: { finished in
                    if let grid = self.gridController {
                        grid.didMoveToParentViewController(self)
                    }
                })
        }
    }

    func hideGrid() {
        if let gc = gridController {
            // Remember previous content offset
            currentGridContentOffset = gc.collectionView!.contentOffset
            
            // Restore action button if it was removed
            if gridPreviousRightNavItem == actionButton && actionButton != nil {
                navigationItem.setRightBarButtonItem(gridPreviousRightNavItem, animated: true)
            }
            
            // Position prior to hide animation
            let pagingFrame = frameForPagingScrollView
            pagingScrollView.frame = CGRectOffset(
                pagingFrame,
                0,
                (self.startOnGrid ? 1 : -1) * pagingFrame.size.height)
            
            // Remember and remove controller falsew so things can detect a nil grid controller
            let tmpGridController = gc
            gridController = nil
            
            // Update
            updateNavigation()
            updateVisiblePageStates()
            
            // Animate, hide grid and show paging scroll view
            UIView.animateWithDuration(
                0.3,
                animations: {
                    tmpGridController.view.frame = CGRectOffset(self.view.bounds, 0, (self.startOnGrid ? -1 : 1) * self.view.bounds.size.height)
                    self.pagingScrollView.frame = self.frameForPagingScrollView
                },
                completion: { finished in
                    tmpGridController.willMoveToParentViewController(nil)
                    tmpGridController.view.removeFromSuperview()
                    tmpGridController.removeFromParentViewController()
            
                    self.setControlsHidden(false, animated: true, permanent: false) // retrigger timer
                })
        }
    }

    //MARK: - Control Hiding / Showing

    // If permanent then we don't set timers to hide again
    // Fades all controls on iOS 5 & 6, and iOS 7 controls slide and fade
    func setControlsHidden(var hidden: Bool, animated: Bool, permanent: Bool) {
        // Force visible
        if 0 == numberOfPhotos || gridController != nil || alwaysShowControls {
            hidden = false
        }
        
        // Cancel any timers
        cancelControlHiding()
        
        // Animations & positions
        let animatonOffset = CGFloat(20)
        let animationDuration = CFTimeInterval(animated ? 0.35 : 0.0)
        
        // Status bar
        if !leaveStatusBarAlone {
            // Hide status bar
            if !isVCBasedStatusBarAppearance {
                // falsen-view controller based
                UIApplication.sharedApplication().setStatusBarHidden(
                    hidden, withAnimation:
                    animated ? UIStatusBarAnimation.Slide : UIStatusBarAnimation.None)
                
            }
            else {
                // View controller based so animate away
                statusBarShouldBeHidden = hidden
                UIView.animateWithDuration(
                    animationDuration,
                    animations: {
                        self.setNeedsStatusBarAppearanceUpdate()
                    })
            }
        }
        
        // Toolbar, nav bar and captions
        // Pre-appear animation positions for sliding
        if areControlsHidden && !hidden && animated {
            // Toolbar
            toolbar.frame = CGRectOffset(frameForToolbarAtOrientation(interfaceOrientation), 0, animatonOffset)
            
            // Captions
            for page in visiblePages {
                if let v = page.captionView {
                    // Pass any index, all we're interested in is the Y
                    var captionFrame = frameForCaptionView(v, index: 0)
                    captionFrame.origin.x = v.frame.origin.x // Reset X
                    v.frame = CGRectOffset(captionFrame, 0, animatonOffset)
                }
            }
        }
        
        UIView.animateWithDuration(animationDuration, animations: {
            let alpha = CGFloat(hidden ? 0.0 : 1.0)

            // Nav bar slides up on it's own on iOS 7+
            if let navi = self.navigationController {
                navi.navigationBar.alpha = alpha
            }
            
            // Toolbar
            self.toolbar.frame = self.frameForToolbarAtOrientation(self.interfaceOrientation)
            
            if hidden {
                self.toolbar.frame = CGRectOffset(self.toolbar.frame, 0, animatonOffset)
            }
            self.toolbar.alpha = alpha

            // Captions
            for page in self.visiblePages {
                if let v = page.captionView {
                    // Pass any index, all we're interested in is the Y
                    var captionFrame = self.frameForCaptionView(v, index: 0)
                    captionFrame.origin.x = v.frame.origin.x // Reset X
                    
                    if hidden {
                        captionFrame = CGRectOffset(captionFrame, 0, animatonOffset)
                    }
                    
                    v.frame = captionFrame
                    v.alpha = alpha
                }
            }
            
            // Selected buttons
            for page in self.visiblePages {
                if let button = page.selectedButton {
                    let v = button
                    var newFrame = self.frameForSelectedButton(v, atIndex: 0)
                    newFrame.origin.x = v.frame.origin.x
                    v.frame = newFrame
                }
            }

        })
        
        // Control hiding timer
        // Will cancel existing timer but only begin hiding if
        // they are visible
        if !permanent {
            hideControlsAfterDelay()
        }
    }

    override func prefersStatusBarHidden() -> Bool {
        if !leaveStatusBarAlone {
            return statusBarShouldBeHidden
        }
        
        return presentingViewControllerPrefersStatusBarHidden
    }

    override func preferredStatusBarStyle() -> UIStatusBarStyle {
        return .LightContent
    }

    override func preferredStatusBarUpdateAnimation() -> UIStatusBarAnimation {
        return .Slide
    }

    func cancelControlHiding() {
        // If a timer exists then cancel and release
        if controlVisibilityTimer != nil {
            controlVisibilityTimer!.invalidate()
            controlVisibilityTimer = nil
        }
    }

    // Enable/disable control visiblity timer
    func hideControlsAfterDelay() {
        if !areControlsHidden {
            cancelControlHiding()
            
            controlVisibilityTimer = NSTimer.scheduledTimerWithTimeInterval(
                delayToHideElements,
                target: self,
                selector: Selector("hideControls"),
                userInfo: nil,
                repeats: false)
        }
    }

    var areControlsHidden: Bool {
        return 0.0 == toolbar.alpha
    }
    
    func hideControls() {
        setControlsHidden(true, animated: true, permanent: false)
    }
    
    func showControls() {
        setControlsHidden(false, animated: true, permanent: false)
    }
    
    func toggleControls() {
        setControlsHidden(!areControlsHidden, animated: true, permanent: false)
    }

    //MARK: - Properties

    var currentPhotoIndex: Int {
        set(i) {
            var index = i
        
            // Validate
            let photoCount = numberOfPhotos
        
            if 0 == photoCount {
                index = 0
            }
            else
            if index >= photoCount {
                index = photoCount - 1
            }
            
            currentPageIndex = index
        
            if isViewLoaded() {
                jumpToPageAtIndex(index, animated: false)
                if !viewIsActive {
                    tilePages() // Force tiling if view is falset visible
                }
            }
        }
        
        get {
            return currentPageIndex
        }
    }

    //MARK: - Misc

    func doneButtonPressed(sender: AnyObject) {
        // Only if we're modal and there's a done button
        if doneButton != nil {
            // See if we actually just want to show/hide grid
            if enableGrid {
                if startOnGrid && nil == gridController {
                    showGrid(true)
                    return
                }
                else
                if !startOnGrid && gridController != nil {
                    hideGrid()
                    return
                }
            }
        
            // Dismiss view controller
            // Call delegate method and let them dismiss us
            if let d = delegate {
                d.photoBrowserDidFinishModalPresentation(self)
            }
            // dismissViewControllerAnimated:true completion:nil]
        }
    }

    //MARK: - Actions

    func actionButtonPressed(sender: AnyObject) {
        // Only react when image has loaded
        if let photo = photoAtIndex(currentPageIndex) {
            if numberOfPhotos > 0 && photo.underlyingImage != nil {
                // If they have defined a delegate method then just message them
                // Let delegate handle things
                if let d = delegate {
                    d.actionButtonPressedForPhotoAtIndex(currentPageIndex, photoBrowser: self)
                }
                /*
                // Show activity view controller
                NSMutableArray *items = [NSMutableArray arrayWithObject:[photo underlyingImage]]
                if photo.caption {
                    [items addObject:photo.caption]
                }
                self.activityViewController = UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil]
                
                // Show loading spinner after a couple of seconds
                double delayInSeconds = 2.0
                dispatchtimet popTime = dispatchtime(DISPATCHTIMENOW, (int64t)(delayInSeconds * NSECPERSEC))
                dispatchafter(popTime, dispatchgetmainqueue(), ^(void){
                    if self.activityViewController {
                        showProgressHUDWithMessage:nil]
                    }
                })

                // Show
                typeof(self) weak weakSelf = self
                [self.activityViewController setCompletionHandler:^(NSString *activityType, BOOL completed) {
                    weakSelf.activityViewController = nil
                    [weakSelf hideControlsAfterDelay]
                    [weakSelf hideProgressHUD:true]
                }]
            
                self.activityViewController.popoverPresentationController.barButtonItem = actionButton
            
                presentViewController(activityViewController, animated: true, completion: nil)
                */
                
                // Keep controls hidden
                setControlsHidden(false, animated: true, permanent: true)
            }
        }
    }

    //MARK: - Action Progress

    var mwProgressHUD: MBProgressHUD?

    var progressHUD: MBProgressHUD {
        if nil == mwProgressHUD {
            mwProgressHUD = MBProgressHUD(view: self.view)
            mwProgressHUD!.minSize = CGSizeMake(120, 120)
            mwProgressHUD!.minShowTime = 1.0
            
            view.addSubview(mwProgressHUD!)
        }
        return mwProgressHUD!
    }

    func showProgressHUDWithMessage(message: String) {
        progressHUD.labelText = message
        progressHUD.mode = MBProgressHUDMode.Indeterminate
        progressHUD.show(true)
        
        if let navi = navigationController {
            navi.navigationBar.userInteractionEnabled = false
        }
    }

    func hideProgressHUD(animated: Bool) {
        progressHUD.hide(animated)
        
        if let navi = navigationController {
            navi.navigationBar.userInteractionEnabled = true
        }
    }

    func showProgressHUDCompleteMessage(message: String?) {
        if let msg = message {
            if progressHUD.hidden {
                progressHUD.show(true)
            }
    
            progressHUD.labelText = msg
            progressHUD.mode = MBProgressHUDMode.CustomView
            progressHUD.hide(true, afterDelay: 1.5)
        }
        else {
            progressHUD.hide(true)
        }
    
        if let navi = navigationController {
            navi.navigationBar.userInteractionEnabled = true
        }
    }
}

protocol PhotoBrowserDelegate: class {
    func numberOfPhotosInPhotoBrowser(photoBrowser: PhotoBrowser) -> Int
    func photoAtIndex(index: Int, photoBrowser: PhotoBrowser) -> Photo

    func thumbPhotoAtIndex(index: Int, photoBrowser: PhotoBrowser) -> Photo
    func captionViewForPhotoAtIndex(index: Int, photoBrowser: PhotoBrowser) -> CaptionView?
    func titleForPhotoAtIndex(index: Int, photoBrowser: PhotoBrowser) -> String
    func didDisplayPhotoAtIndex(index: Int, photoBrowser: PhotoBrowser)
    func actionButtonPressedForPhotoAtIndex(index: Int, photoBrowser: PhotoBrowser)
    func isPhotoSelectedAtIndex(index: Int, photoBrowser: PhotoBrowser) -> Bool
    func selectedChanged(selected: Bool, index: Int, photoBrowser: PhotoBrowser)
    func photoBrowserDidFinishModalPresentation(photoBrowser: PhotoBrowser)
}