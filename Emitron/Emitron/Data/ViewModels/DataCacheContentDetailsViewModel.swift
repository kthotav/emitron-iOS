/// Copyright (c) 2020 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import Foundation

final class DataCacheContentDetailsViewModel: ContentDetailsViewModel {
  private let repository: Repository
  private let service: ContentsService
  
  init(contentId: Int, repository: Repository, service: ContentsService) {
    self.repository = repository
    self.service = service
    super.init(contentId: contentId)
  }
  
  override func configureSubscriptions() {
    repository.contentDetailState(for: contentId)
      .sink(receiveCompletion: { [weak self] (completion) in
        guard let self = self else { return }
        if case .failure(let error) = completion, (error as? DataCacheError) == DataCacheError.cacheMiss {
          self.getContentDetailsFromService()
        } else {
          self.state = .failed
          // TODO logging
          print("Unable to retrieve download content detail: \(completion)")
        }
        }, receiveValue: { [weak self] (contentDetailState) in
          guard let self = self else { return }
          
          self.state = .hasData
          self.content = contentDetailState
      })
      .store(in: &subscriptions)
    
    self.$content
      .compactMap({ $0 })
      .map(\ContentDetailDisplayable.childContents)
      .removeDuplicates()
      .map({ $0.map({ content in content.id }) })
      .sink(receiveValue: { [weak self] (childContentIds) in
        guard let self = self else { return }
        self.state = .loadingAdditional
        self.childContentsPublishers.send(
          self.repository.contentSummaryState(for: childContentIds)
        )
      })
      .store(in: &subscriptions)
    
    childContentsPublishers
      .switchToLatest()
      .sink(receiveCompletion: { [weak self] (completion) in
        guard let self = self else { return }
        if case .failure(let error) = completion, (error as? DataCacheError) == DataCacheError.cacheMiss {
          self.getContentDetailsFromService()
        } else {
          self.state = .failed
          // TODO logging
          print("Unable to retrieve download child contents detail: \(completion)")
        }
        }, receiveValue: { [weak self] (contentSumaryStates) in
          guard let self = self else { return }
          self.state = .hasData
          self.childContents = contentSumaryStates
      })
      .store(in: &subscriptions)
  }
  
  private func getContentDetailsFromService() {
    self.state = .loading
    service.contentDetails(for: contentId) { (result) in
      switch result {
      case .failure(let error):
        self.state = .failed
        Failure
          .fetch(from: String(describing: type(of: self)), reason: error.localizedDescription)
          .log(additionalParams: nil)
      case .success(let (_, cacheUpdate)):
        self.repository.apply(update: cacheUpdate)
        self.reload()
      }
    }
  }
}
