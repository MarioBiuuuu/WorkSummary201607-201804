//
//  ListService.swift
//  RxTodo
//
//  Created by luhe liu on 2018/5/16.
//  Copyright © 2018年 Suyeol Jeon. All rights reserved.
//

import UIKit
import Alamofire
import RxSwift
import RxCocoa
import RxDataSources
import ReactorKit

public typealias Result = Alamofire.Result

// MARK: - 基础列表服务
open class RxBasicCollectionService {
    
    /// 列表事件
    public enum Event {
        /// 请求事件，参数：页数、列表数据
        case request(page: Int, result: Result<[SectionType]>)
        /// 排序事件，参数：列表数据
        case sort(result: [SectionType])
        /// 选中元素事件，参数：选中元素
        case didSelectedItem(ItemType)
        /// 选择元素事件，参数：选择元素、列表数据
        case selectItems([ItemType], result: [SectionType])
        /// 选择索引事件，参数：选择索引、列表数据
        case selectIndexes([IndexType], result: [SectionType])
        /// 插入事件，参数：插入表、列表数据
        case insertItems([IndexType: ItemType], result: [SectionType])
        /// 删除元素事件，参数：删除元素、列表数据
        case deleteItems([ItemType], result: [SectionType])
        /// 删除索引事件，参数：删除索引、列表数据
        case deleteIndexes([IndexType], result: [SectionType])
        /// 更新元素事件，参数：更新元素、列表数据
        case updateItems([ItemType], result: [SectionType])
        /// 更新组事件，参数：更新组、列表数据
        case updateSections([SectionType], result: [SectionType])
        /// 替换元素事件，参数：替换表、列表数据
        case replaceItems([IndexType: ItemType], result: [SectionType])
    }
    
    /// 类型
    public typealias IndexType = IndexPath
    public typealias ItemType = RxBasicListItem
    public typealias Section = RxBasicListSection
    public typealias SectionType = AnimatableSectionModel<Section, ItemType>
    
    /// 属性
    open var deletedItemsCache: [ItemType] = []
    open var sections: [SectionType] = []
    open var needCacheDeleted: Bool = false
    open var isSelectedNext: Bool = false
    open var isSelectedForReloadData: Bool = false
    open var isCachePageData: Bool = false
    open var event = PublishSubject<Event>()
    
    //MARK: 返回可检测数据，可能触发 event 的方法
    /// 获取列表数据，不会触发 event
    open func fetchSections() -> Observable<[SectionType]> {
        return .just(self.sections)
    }
    /// 保存列表数据，不会触发 event
    open func saveSections(_ sections: [SectionType]) -> Observable<[SectionType]> {
        self.sections = sections
        return .just(sections)
    }
    /// 列表网络请求 + 返回处理，会触发 event
    open func fetchData(page: Int) -> Observable<Result<[SectionType]>> {
        return self.fetchSections()
            .flatMap({ [weak self] (sections) -> Observable<Result<[SectionType]>> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.request(page: page, sections: sections)
                    .flatMap({ [weak self] (result) -> Observable<Result<[SectionType]>> in
                        guard let strongSelf = self else { return .empty() }
                        let responseResult = strongSelf.handleResponse(result, page: page, sections: sections)
                        if let newSections = responseResult.value {
                            return strongSelf.saveSections(newSections).map({ Result.success($0) })
                        }
                        return .just(responseResult)
                    })
            })
            .do(onNext: { [weak self] result in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.request(page: page, result: result))
            })
    }
    /// 列表网络请求，子类进行重载该方法，不会触发 event
    open func request(page: Int, sections: [SectionType]) -> Observable<Result<[SectionType]>> {
        return .just(.success([]))
    }
    /// 列表排序，会触发 event
    open func sort() -> Observable<[SectionType]> {
        return self.fetchSections()
            .flatMap({ [weak self] (sections) -> Observable<[SectionType]> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.saveSections(strongSelf.sort(sections: sections))
            })
            .do(onNext: { [weak self] sections in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.sort(result: sections))
            })
    }
    /// 列表选中元素，会触发 event
    open func select(items: [ItemType]) -> Observable<[SectionType]> {
        if !isSelectedForReloadData {
            if let item = items.last {
                self.event.onNext(.didSelectedItem(item))
            }
            return .empty()
        }
        return self.fetchSections()
            .flatMap({ [weak self] (sections) -> Observable<[SectionType]> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.saveSections(strongSelf.select(items: items, sections: sections))
            })
            .do(onNext: { [weak self] sections in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.selectItems(items, result: sections))
            })
    }
    /// 列表选中索引，会触发 event
    open func select(indexes: [IndexType]) -> Observable<[SectionType]> {
        if !isSelectedForReloadData {
            if let index = indexes.last, let item = find(index: index, sections: sections) {
                self.event.onNext(.didSelectedItem(item))
            }
            return .empty()
        }
        return self.fetchSections()
            .flatMap({ [weak self] (sections) -> Observable<[SectionType]> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.saveSections(strongSelf.select(indexes: indexes, sections: sections))
            })
            .do(onNext: { [weak self] sections in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.selectIndexes(indexes, result: sections))
            })
    }
    /// 列表插入元素，会触发 event
    open func insert(items: [IndexType: ItemType]) -> Observable<[SectionType]> {
        return self.fetchSections()
            .flatMap({ [weak self] (sections) -> Observable<[SectionType]> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.saveSections(strongSelf.insert(items: items, sections: sections))
            })
            .do(onNext: { [weak self] sections in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.insertItems(items, result: sections))
            })
    }
    /// 列表删除具体元素，会触发 event
    open func delete(items: [ItemType]) -> Observable<[SectionType]> {
        return self.fetchSections()
            .flatMap({ [weak self] (sections) -> Observable<[SectionType]> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.saveSections(strongSelf.delete(items: items, sections: sections))
            })
            .do(onNext: { [weak self] sections in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.deleteItems(items, result: sections))
            })
    }
    /// 根据索引删除元素，会触发 event
    open func delete(indexes: [IndexType]) -> Observable<[SectionType]> {
        return self.fetchSections()
            .flatMap({ [weak self] (sections) -> Observable<[SectionType]> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.saveSections(strongSelf.delete(indexes: indexes, sections: sections))
            })
            .do(onNext: { [weak self] sections in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.deleteIndexes(indexes, result: sections))
            })
    }
    /// 更新元素，会触发 event
    open func update(items: [ItemType]) -> Observable<[SectionType]> {
        return self.fetchSections()
            .flatMap({ [weak self] (sections) -> Observable<[SectionType]> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.saveSections(strongSelf.update(items: items, sections: sections))
            })
            .do(onNext: { [weak self] sections in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.updateItems(items, result: sections))
            })
    }
    /// 更新一组或多组元素，会触发 event
    open func update(sections: [SectionType]) -> Observable<[SectionType]> {
        return self.fetchSections()
            .flatMap({ [weak self] (oldSections) -> Observable<[SectionType]> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.saveSections(strongSelf.update(newSections: sections, sections: oldSections))
            })
            .do(onNext: { [weak self] newSections in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.updateSections(sections, result: newSections))
            })
    }
    /// 根据索引替换元素，会触发 event
    open func replace(items: [IndexType: ItemType]) -> Observable<[SectionType]> {
        return self.fetchSections()
            .flatMap({ [weak self] (sections) -> Observable<[SectionType]> in
                guard let strongSelf = self else { return .empty() }
                return strongSelf.saveSections(strongSelf.replace(items: items, sections: sections))
            })
            .do(onNext: { [weak self] sections in
                guard let strongSelf = self else { return }
                strongSelf.event.onNext(.replaceItems(items, result: sections))
            })
    }
    
    //MARK: 逻辑功能处理方法，可通过重载修改逻辑实现
    /// 处理请求返回
    open func handleResponse(_ response: Result<[SectionType]>, page: Int, sections: [SectionType]) -> Result<[SectionType]> {
        guard let value = response.value else { return response }
        var handledSections = sections
        let isLoadMore = page > 1
        if isLoadMore || isCachePageData {
            handledSections = mergeSections(sections, with: value, isLoadMore: isLoadMore)
        } else {
            handledSections = value
        }
        return .success(handledSections)
    }
    /// 列表排序
    open func sort(sections: [SectionType]) -> [SectionType] {
        return sections
    }
    /// 列表选中索引
    open func select(indexes: [IndexType], sections: [SectionType]) -> [SectionType] {
        if isSelectedNext {
            return selectNext(indexes: indexes, sections: sections)
        } else {
            return selectNew(indexes: indexes, sections: sections)
        }
    }
    /// 列表选中元素
    open func select(items: [ItemType], sections: [SectionType]) -> [SectionType] {
        if isSelectedNext {
            return selectNext(items: items, sections: sections)
        } else {
            return selectNew(items: items, sections: sections)
        }
    }
    /// 列表选中新选项组，移出之前选项组
    open func selectNew(indexes: [IndexType], sections: [SectionType]) -> [SectionType] {
        for (sectionIndex, section) in sections.enumerated() {
            for (itemIndex, item) in section.items.enumerated() {
                if indexes.contains(IndexPath(row: itemIndex, section: sectionIndex)) {
                    item.didSelected = true
                } else {
                    item.didSelected = false
                }
            }
        }
        return sections
    }
    /// 列表选中新选项组，移出之前选项组
    open func selectNew(items: [ItemType], sections: [SectionType]) -> [SectionType] {
        for section in sections {
            for item in section.items {
                if items.filter({ $0.identity == item.identity }).count > 0 {
                    item.didSelected = true
                } else {
                    item.didSelected = false
                }
            }
        }
        return sections
    }
    /// 列表选中下一个选项组到原来选项组，选中2次表示不选择
    open func selectNext(indexes: [IndexType], sections: [SectionType]) -> [SectionType] {
        indexes.forEach { (index) in
            if let item = find(index: index, sections: sections) {
                item.didSelected = !item.didSelected
            }
        }
        return sections
    }
    /// 列表选中下一个选项组到原来选项组，选中2次表示不选择
    open func selectNext(items: [ItemType], sections: [SectionType]) -> [SectionType] {
        for section in sections {
            for item in section.items {
                if items.filter({ $0.identity == item.identity }).count > 0 {
                    item.didSelected = !item.didSelected
                }
            }
        }
        return sections
    }
    /// 列表插入元素
    open func insert(items: [IndexType: ItemType], sections: [SectionType]) -> [SectionType] {
        let soredItems = items.sorted(by: { $0.key < $1.key })
        var newSections: [SectionType] = sections
        soredItems.forEach { (key, value) in
            if var newSection = sections.safeIndex(key.section) {
                if key.item >= 0 && key.item < newSection.items.count {
                    var newItems = newSection.items
                    newItems.insert(value, at: key.item)
                    newSection.items = newItems
                    newSection.model.totalCount += 1
                    newSections[key.section] = newSection
                }
            }
        }
        return newSections
    }
    /// 列表删除元素，根据具体要删除的元素
    open func delete(items: [ItemType], sections: [SectionType]) -> [SectionType] {
        var newSections: [SectionType] = []
        sections.forEach { (section) in
            var newSection = section
            var newItems: [ItemType] = []
            newSection.items.forEach({ (item) in
                if items.filter({ $0.identity == item.identity }).count == 0 {
                    newItems.append(item)
                } else {
                    if needCacheDeleted {
                        deletedItemsCache.append(item)
                    }
                    newSection.model.totalCount -= 1
                }
            })
            newSection.items = newItems
            newSections.append(newSection)
        }
        return newSections
    }
    /// 列表删除元素，根据要删除的索引
    open func delete(indexes: [IndexType], sections: [SectionType]) -> [SectionType] {
        var newSections: [SectionType] = []
        for (sectionIndex, section) in sections.enumerated() {
            if indexes.filter({ $0.section == sectionIndex }).count > 0 {
                var newSection = section
                var newItems: [ItemType] = []
                for (itemIndex, item) in newSection.items.enumerated() {
                    if indexes.filter({ $0.section == sectionIndex && $0.item == itemIndex }).count == 0 {
                        newItems.append(item)
                    } else {
                        if needCacheDeleted {
                            deletedItemsCache.append(item)
                        }
                        newSection.model.totalCount -= 1
                    }
                }
                newSection.items = newItems
                newSections.append(newSection)
            } else {
                newSections.append(section)
            }
        }
        return newSections
    }
    /// 列表更新元素
    open func update(items: [ItemType], sections: [SectionType]) -> [SectionType] {
        var newSections = sections
        for (sectionIndex, var section) in sections.enumerated() {
            var newItems = section.items
            for (itemIndex, oldItem) in section.items.enumerated() {
                if let newItem = items.filter({ $0.identity == oldItem.identity }).first {
                    newItems[itemIndex] = newItem
                }
            }
            section.items = newItems
            newSections[sectionIndex] = section
        }
        return newSections
    }
    /// 列表更新组
    open func update(newSections: [SectionType], sections: [SectionType]) -> [SectionType] {
        var updatedSections = sections
        for (sectionIndex, section) in sections.enumerated() {
            if let newSection = newSections.filter({ $0.identity == section.identity }).first {
                updatedSections[sectionIndex] = newSection
            }
        }
        return updatedSections
    }
    /// 列表替换某个元素
    open func replace(items: [IndexType: ItemType], sections: [SectionType]) -> [SectionType] {
        var newSections = sections
        for (sectionIndex, var section) in sections.enumerated() {
            var newItems = section.items
            for (itemIndex, _) in section.items.enumerated() {
                if let newItem = items.filter({ $0.key == IndexPath(row: itemIndex, section: sectionIndex) }).first {
                    newItems[itemIndex] = newItem.value
                }
            }
            section.items = newItems
            newSections[sectionIndex] = section
        }
        return newSections
    }
    /// 列表查找元素
    open func find(index: IndexType, sections: [SectionType]) -> ItemType? {
        if let section = sections.safeIndex(index.section) {
            return section.items.safeIndex(index.item)
        }
        return nil
    }
    /// 列表批量查找元素
    open func find(indexes: [IndexType], sections: [SectionType]) -> [IndexType: ItemType] {
        var result: [IndexType: ItemType] = [:]
        indexes.forEach { (index) in
            result[index] = find(index: index, sections: sections)
        }
        return result
    }
    /// 批量合并多组的所有元素
    open func mergeSections(_ oldSetions: [SectionType], with sections: [SectionType], isLoadMore: Bool) -> [SectionType] {
        var newSections: [SectionType] = []
        oldSetions.forEach { (oldSection) in
            if let section = sections.filter({ $0.model.identity == oldSection.model.identity }).first {
                let newSection = mergeSection(oldSection, with: section, isLoadMore: isLoadMore)
                newSections.append(newSection)
            } else {
                newSections.append(oldSection)
            }
        }
        return newSections
    }
    /// 合并一组的所有元素
    open func mergeSection(_ oldSetion: SectionType, with section: SectionType, isLoadMore: Bool) -> SectionType {
        var newSection = oldSetion
        let currentItems = oldSetion.items
        // 过滤之前手动删除的 cell
        var filterItems = currentItems
        if needCacheDeleted {
            filterItems += deletedItemsCache
        }
        var newItems: [ItemType] = []
        section.items.forEach { item in
            if let oldItem = filterItems.filter({ return $0.identity == item.identity }).first {
                mergeUpdateItem(oldItem, newItem: item)
            } else {
                newItems.append(item)
            }
        }
        if isLoadMore { // 加载更多是尾部递增，总数不变
            newSection.items = currentItems + newItems
            newSection.model.totalCount = max(section.model.totalCount, oldSetion.model.totalCount)
        } else { // 加载第一页是顶部递增, 并且总数增加
            newSection.items = newItems + currentItems
            newSection.model.totalCount = max(section.model.totalCount, oldSetion.model.totalCount + newItems.count)
        }
        newSection.model.totalCount = max(newSection.model.totalCount, newSection.items.count)
        newSection.model.canLoadMore = section.model.canLoadMore
        return newSection
    }
    /// 合并中对旧元素的更新操作
    open func mergeUpdateItem(_ oldItem: ItemType, newItem: ItemType) {
    }
}
